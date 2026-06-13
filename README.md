# World Cup 2026 · Match Tracker

A single-page web app for following the 2026 FIFA World Cup — fill in scores, watch the
group standings update live, and see the knockout bracket build itself as results come in.

The whole thing is one self-contained `index.html` file: no build step, no backend, no
dependencies. Open it in a browser and it works.

## Features

- **Fixtures** — every match in the tournament, grouped by matchday, with kickoff times
  shown in your chosen timezone. Today's matches are highlighted.
- **Groups** — live group tables that recompute as you enter results, with qualification
  and best-third-place placings shaded in.
- **Knockout** — the bracket fills in automatically from group standings and round results.
- **Timezone picker** — display all kickoff times in any timezone.
- **Local persistence** — entered scores are saved to `localStorage`, so your predictions
  survive a refresh.
- **Import / Export** — back up or share your results as a JSON file.
- **Shared results feed** — on load the app fetches `worldcup2026-results.json` from this
  repo so the published set of actual results stays in sync.

## Usage

Open `index.html` in any modern browser — that's it. Enter scores in the Fixtures tab and
the Groups and Knockout views update automatically.

To host it, serve the repo as static files (e.g. GitHub Pages); no server-side code is
required.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | The entire application — markup, styles, and logic. |
| `worldcup2026-results.json` | Published actual match results, fetched on load. |
| `favicon.svg` | App icon. |
