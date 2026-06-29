# World Cup 2026 · Match Tracker

A single-page web app for following the 2026 FIFA World Cup — fill in scores, watch the
group standings update live, and see the knockout bracket build itself as results come in.

The whole thing is one self-contained `index.html` file: no build step, no backend, no
dependencies. Open it in a browser and it works.

## Features

- **Fixtures** — every match in the tournament, grouped by matchday, with kickoff times
  shown in your chosen timezone. Today's matches are highlighted, and each one expands to
  a head-to-head **form panel** comparing the two teams' tournament form so far — points,
  goal difference, goals scored, and their recent win/draw/loss results.
- **Groups** — live group tables that recompute as you enter results, with qualification
  and best-third-place placings shaded in.
- **Knockout** — the bracket fills in automatically from group standings and round results.
- **Radial** — the same knockout bracket drawn as a circular sunburst, with the champion
  at the centre.
- **Timezone picker** — display all kickoff times in any timezone.
- **Local persistence** — entered scores are saved to `localStorage`, so your predictions
  survive a refresh.
- **Import / Export** — back up or share your results as a JSON file.
- **Shared results feed** — on load the app fetches `worldcup2026-results.json` from this
  repo so the published set of actual results stays in sync.

## Usage

Open `index.html` in any modern browser — that's it. Enter scores in the Fixtures tab and
the Groups, Knockout, and Radial views update automatically.

To host it, serve the repo as static files (e.g. GitHub Pages); no server-side code is
required.

## Keeping results up to date

`update-results.sh` pulls finished matches from FIFA's public calendar API and writes the
scores into `worldcup2026-results.json` — group matches matched by team pair, knockout
matches by round/city/date, including penalty-shootout winners. It needs `curl` and `jq`.

```sh
./update-results.sh            # fill only empty entries
./update-results.sh --force    # also overwrite already-filled entries
./update-results.sh --dry-run  # show what would change, write nothing
```

A GitHub Actions workflow (`.github/workflows/update-results.yml`) runs this hourly and
commits any new scores, so the published feed stays current on its own.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | The entire application — markup, styles, and logic. |
| `worldcup2026-results.json` | Published actual match results, fetched on load. |
| `update-results.sh` | Fetches finished match scores from the FIFA API. |
| `.github/workflows/update-results.yml` | Hourly GitHub Action that runs the updater. |
| `favicon.svg` | App icon. |
