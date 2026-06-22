#!/usr/bin/env bash
#
# update-results.sh — fill worldcup2026-results.json from the FIFA API.
#
# Pulls finished World Cup 2026 matches from FIFA's public calendar API and
# writes scores for any entry that isn't filled in yet. Group matches are
# matched by team pair; knockout matches by round + city + date (teams there
# are still placeholders until the bracket resolves). Penalty shootouts set
# {pen:"h"|"a"} on level knockout matches.
#
# Usage:
#   ./update-results.sh                 # fill only empty entries
#   ./update-results.sh --force         # also overwrite already-filled entries
#   ./update-results.sh --season 285023 # override auto-discovered season id
#   ./update-results.sh --dry-run       # show what would change, write nothing
#
# Requires: curl, jq (same deps as the Alfred workflow this is derived from).

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
FORCE=false
DRY_RUN=false
SEASON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --season)  SEASON="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "Missing dependency: $dep" >&2; exit 1; }
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_HTML="$SCRIPT_DIR/index.html"
RESULTS_JSON="$SCRIPT_DIR/worldcup2026-results.json"
[[ -f "$INDEX_HTML" ]] || { echo "Cannot find index.html at $INDEX_HTML" >&2; exit 1; }

API="https://api.fifa.com/api/v3"
CURL=(curl -sf --compressed --connect-timeout 10 -L)

TMP_SCHED="$(mktemp -t wc2026sched)"
trap 'rm -f "$TMP_SCHED"' EXIT

# ---------------------------------------------------------------------------
# 1. Discover the 2026 World Cup season id (IdCompetition 17), unless overridden
# ---------------------------------------------------------------------------
if [[ -z "$SEASON" ]]; then
  SEASON="$("${CURL[@]}" "$API/calendar/matches?language=en&count=1&IdCompetition=17&from=2026-01-01" \
    | jq -r '.Results[0].IdSeason // empty')"
  [[ -n "$SEASON" ]] || { echo "Could not discover the 2026 World Cup season id." >&2; exit 1; }
fi
echo "Using FIFA season id: $SEASON"

# ---------------------------------------------------------------------------
# 2. Download the full schedule
# ---------------------------------------------------------------------------
"${CURL[@]}" "$API/calendar/matches?language=en&count=500&idSeason=$SEASON" -o "$TMP_SCHED" \
  || { echo "Failed to download schedule." >&2; exit 1; }
echo "Downloaded $(jq '.Results | length' "$TMP_SCHED") matches."

# ---------------------------------------------------------------------------
# 3. Parse the fixture tables out of index.html (single source of truth).
#    Each array element is already valid JSON once the trailing comma is gone,
#    so `jq -s` slurps the lines into an array of arrays.
# ---------------------------------------------------------------------------
extract_array() {
  # $1 = JS const name; prints a JSON array of arrays for that table.
  awk -v name="const $1 = [" '
    index($0, name) { f=1; next }
    /\]\.map/        { f=0 }
    f
  ' "$INDEX_HTML" | sed 's/,[[:space:]]*$//' | jq -s '.'
}

GROUP_RAW="$(extract_array GROUP_MATCHES)"
KO_RAW="$(extract_array KO_MATCHES)"
[[ "$(jq 'length' <<<"$GROUP_RAW")" -gt 0 ]] || { echo "Failed to parse GROUP_MATCHES from index.html." >&2; exit 1; }
[[ "$(jq 'length' <<<"$KO_RAW")" -gt 0 ]]    || { echo "Failed to parse KO_MATCHES from index.html." >&2; exit 1; }

# Group fixtures: [id, grp, utc, home, away, city]
GROUP_FIX="$(jq '[.[] | {id:.[0], home:.[3], away:.[4]}]' <<<"$GROUP_RAW")"
# Knockout fixtures: [n, round, utc, city, homeSpec, awaySpec]
KO_FIX="$(jq '[.[] | {id:("k"+(.[0]|tostring)), round:.[1], utc:.[2], city:.[3]}]' <<<"$KO_RAW")"

# Existing results (default to {} if absent/empty)
if [[ -s "$RESULTS_JSON" ]]; then
  EXISTING="$(cat "$RESULTS_JSON")"
else
  EXISTING="{}"
fi

# ---------------------------------------------------------------------------
# 4. Match FIFA results to fixtures and merge.
# ---------------------------------------------------------------------------
read -r -d '' JQ_PROG <<'JQ' || true
# --- normalization tables -------------------------------------------------
def teamAlias:
  { "korea republic":"south korea",
    "usa":"united states",
    "côte d'ivoire":"ivory coast",
    "cabo verde":"cape verde",
    "ir iran":"iran",
    "congo dr":"dr congo" };
def cityAlias:
  { "new jersey":"new york new jersey" };
def roundCode:
  { "round of 32":"R32", "round of 16":"R16",
    "quarter-final":"QF", "quarter-finals":"QF",
    "semi-final":"SF",  "semi-finals":"SF",
    "play-off for third place":"3RD", "final":"FINAL" };
def normTeam: ascii_downcase | . as $t | (teamAlias[$t] // $t);
def normCity: ascii_downcase | . as $c | (cityAlias[$c] // $c);
def dayEpoch(s): ((s[0:10]) + "T00:00:00Z") | fromdateiso8601;
def absdiff(x;y): (x - y) | if . < 0 then -. else . end;

# --- lookup indices -------------------------------------------------------
($group | reduce .[] as $g ({};
    . + { (($g.home|ascii_downcase) + "|" + ($g.away|ascii_downcase)): $g.id })) as $gi
| ($ko | reduce .[] as $k ({};
    (($k.round) + "|" + ($k.city|ascii_downcase)) as $key
    | .[$key] += [ {id:$k.id, day: dayEpoch($k.utc)} ])) as $ki

# --- per-match score object ----------------------------------------------
| def scoreObj($m):
    { h: $m.Home.Score, a: $m.Away.Score }
    + ( if ($m.HomeTeamPenaltyScore != null and $m.AwayTeamPenaltyScore != null
            and ($m.HomeTeamPenaltyScore != $m.AwayTeamPenaltyScore)
            and (($m.HomeTeamPenaltyScore > 0) or ($m.AwayTeamPenaltyScore > 0)))
        then { pen: (if $m.HomeTeamPenaltyScore > $m.AwayTeamPenaltyScore then "h" else "a" end) }
        else {} end );

# --- resolve a FIFA match to a fixture id (or empty) ----------------------
def resolve($m):
    ($m.StageName[0].Description) as $stage
    | if ($stage|ascii_downcase) == "first stage" then
        (($m.Home.TeamName[0].Description | normTeam) + "|"
         + ($m.Away.TeamName[0].Description | normTeam)) as $key
        | ($gi[$key] // empty)
      else
        (roundCode[$stage|ascii_downcase]) as $rc
        | if $rc == null then empty
          else
            ($m.Stadium.CityName[0].Description | normCity) as $city
            | ($ki[$rc + "|" + $city] // []) as $cands
            | if ($cands|length) == 0 then empty
              else (dayEpoch($m.Date)) as $md
                   | ($cands | min_by(absdiff(.day; $md))).id
              end
          end
      end;

# --- merge ----------------------------------------------------------------
reduce (.Results[]
        | select(.MatchStatus == 0 and .Home != null and .Away != null
                 and .Home.Score != null and .Away.Score != null)) as $m
  ( { result: $existing, added: [], updated: [] };
    ($m | resolve($m)) as $id
    | if $id == null then .
      else
        (scoreObj($m)) as $v
        | ( ($m.Home.TeamName[0].Description // $m.StageName[0].Description) + " vs "
            + ($m.Away.TeamName[0].Description // ($m.Stadium.CityName[0].Description)) ) as $label
        | ({ id:$id, label:$label } + $v) as $change
        | if ($existing | has($id)) then
            if $force then .result[$id] = $v | .updated += [$change] else . end
          else
            .result[$id] = $v | .added += [$change]
          end
      end )
JQ

# Run the program with the schedule as input; fixtures/results passed as args.
OUT="$(jq \
  --argjson group   "$GROUP_FIX" \
  --argjson ko      "$KO_FIX" \
  --argjson existing "$EXISTING" \
  --argjson force   "$FORCE" \
  "$JQ_PROG" "$TMP_SCHED")"

# ---------------------------------------------------------------------------
# 5. Report and write
# ---------------------------------------------------------------------------
fmt() { jq -r '.[] | "  \(.id): \(.label) — \(.h)-\(.a)\(if .pen then " (pens: " + .pen + ")" else "" end)"'; }

ADDED_N="$(jq '.added | length' <<<"$OUT")"
UPDATED_N="$(jq '.updated | length' <<<"$OUT")"

if [[ "$ADDED_N" -gt 0 ]]; then
  echo "Filled in $ADDED_N new result(s):"
  jq '.added' <<<"$OUT" | fmt
fi
if [[ "$UPDATED_N" -gt 0 ]]; then
  echo "Overwrote $UPDATED_N existing result(s):"
  jq '.updated' <<<"$OUT" | fmt
fi
if [[ "$ADDED_N" -eq 0 && "$UPDATED_N" -eq 0 ]]; then
  echo "No new finished matches to fill in. Nothing to do."
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run — $RESULTS_JSON not modified)"
elif [[ "$ADDED_N" -gt 0 || "$UPDATED_N" -gt 0 ]]; then
  jq '.result' <<<"$OUT" > "$RESULTS_JSON"
  echo "Wrote $RESULTS_JSON"
fi
