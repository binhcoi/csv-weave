# Web interface design

How the browser interface for CSVWeave is built and how it is meant to work:
its goals, its relationship to the API, the screens it will offer, and the
design rules it follows. Setup and commands are in the [README](README.md);
progress is tracked in the [roadmap](ROADMAP.md).

## Goals

1. A web application, usable without constructing API requests by hand.
2. Responsive: actions register quickly.
3. No needless jumping, forced reloads, or janky interactions.
4. Handles large data sets.
5. Rule forms are driven by the catalogs' `input_schema`.
6. The backend may change to accommodate the UI.
7. Looks modern.
8. Easy to use.

The initial interface targets local, single-user use. Authentication and
multi-user hosting are outside the roadmap.

## Architecture

The interface is a single-page application in `frontend/`, written in React and
TypeScript and built with Vite. It talks to the Rails application in `backend/`
only through the JSON API described in [docs/api.md](docs/api.md). The backend
stays API-only and renders no pages.

A client-side application was chosen because the two configuration editors —
ordered columns with several validations each, and maps with per-operation
parameters — hold a lot of unsaved state, and because established component
kits and list virtualization cover goals 3, 4, and 7 as dependencies rather
than project work.

Accepted costs: a second language, toolchain, and security-advisory stream; a
stack assembled from parts rather than prescribed by a framework; and no
enforced contract between the API and the TypeScript code.

Routing is client-side with React Router in declarative mode. The
application's complexity lives in forms and unsaved editor state, not in
routing, so the simplest mainstream router is enough; nested routes map
directly onto the shared navigation shell, and its data mode remains available
if route-level data loading is wanted later.

Components come from Mantine. It covers the interface's center of gravity —
dense, accessible configuration forms, plus overlays and notifications — as
dependencies rather than project work, without adding a styling toolchain such
as Tailwind, and it keeps component code out of the repository (unlike
copy-in kits). Virtualization of long lists is not part of the kit; a
dedicated library is added when the first long list is built.

In development the two applications run side by side, the API on port 3000 and
the Vite dev server on port 5173. They are different origins, so the frontend
needs either a Vite proxy or CORS on the backend to reach the API; see
[Open decisions](#open-decisions).

## What the interface presents

The interface uses the API's vocabulary:

| Term | Meaning |
| --- | --- |
| File type | A reusable CSV format: ordered columns, each with validation rules. |
| Catalog entry | An available validator or transformer, with a JSON Schema for its settings. |
| Rule | A catalog entry applied to a column or map, with its settings. |
| Transformation map | Converts one file type into another; its transformations target destination columns. |
| Data file | An uploaded CSV associated with a file type. |
| Validation run / conversion run | A background job over a data file, with status, counts, and downloadable results. |

## Screens

Three working areas and a help page, reached from a shared navigation shell:

- **File types.** A list of file types and an editor for one: its ordered
  columns, the validation rules on each column, and each rule's settings.
- **Transformation maps.** A list of maps and an editor that shows source and
  destination columns together, so it is clear which source columns feed each
  destination column. Destination columns may stay unmapped.
- **Files and runs.** Upload a CSV for a file type, start a validation or a
  conversion with a compatible map, follow its progress, and download the
  converted file or the rejection report.
- **Help.** Static content explaining the concepts above and the typical
  workflow. Built first, with the navigation shell, because it needs no API
  calls.

## Design principles

- **Schema-driven rule forms.** A rule's settings form is generated from its
  catalog entry's `input_schema`, not written by hand per operation. A new
  validator or transformer then needs no frontend change.
- **The server decides validity.** The API validates every write against the
  same schemas plus processor-specific rules. The UI may check obvious mistakes
  early, but it always shows the server's verdict and maps it back to fields:
  the `errors` object keys, nested paths such as
  `columns[1].validations[0].input_json`, and indexed errors from array
  endpoints (see [Errors](docs/api.md#errors)).
- **Never lose the user's work.** Failed writes are all-or-nothing, so a
  rejected save keeps every unsaved value in the form and highlights what to
  correct.
- **Stable screens.** Navigation happens on the client without page reloads.
  Loading states keep space reserved, so content does not jump when data
  arrives.
- **Built for large data.** Long lists, such as many columns or a long error
  report, render with virtualization. Where the API cannot yet serve data in
  pages, the backend gains that ability (see below) instead of the browser
  downloading everything.
- **Background work is visible.** Starting a run returns `202` with a run to
  poll. The interface shows each run's status and counts until it finishes.
- **Keyboard and screen-size friendly.** Every action is reachable by keyboard,
  and the editors remain usable on narrow screens.

## Expected backend changes

Changes the UI is expected to need, made when the screen that depends on them is
built:

- Saving a whole configuration in one transaction.
- Reordering columns in a single request.
- Richer catalog schemas, such as titles, descriptions, and defaults, so the
  generated forms read well.
- Pagination for list endpoints.
- A preview of an uploaded CSV's first rows.
- Paged error reports.

## Frontend code structure

```text
frontend/
├── index.html            page shell; mounts the app into #root
├── vite.config.ts        dev server and Vitest settings
├── postcss.config.cjs    Mantine's PostCSS preset and breakpoint variables
├── eslint.config.js
└── src/
    ├── main.tsx          entry point; mounts the providers and the router
    ├── App.tsx           the route table
    ├── AppLayout.tsx     the navigation shell wrapped around every page
    ├── themes.ts         candidate Mantine themes: palette, radius, and typography
    ├── DevStylePanel.tsx  temporary dev-only switcher between the candidate themes
    ├── pages/            one component per screen
    ├── components/       shared building blocks used by several screens
    ├── *.test.tsx        unit tests, beside the code they cover
    └── test/             Testing Library setup and the shared render helper
```

- Unit tests use Vitest and Testing Library in jsdom and query the page the way
  a user would, by role and visible text.
- ESLint, with `typescript-eslint` and the React Hooks rules, checks
  correctness; Prettier owns formatting. ESLint was chosen when the foundation
  was planned, before the `create-vite` template switched its default to oxlint.
- TypeScript is pinned to 6.0 because `typescript-eslint` does not yet support
  TypeScript 7. Move to 7 when it does.
- Browser end-to-end tests will live in the root `e2e/` folder, beside the API
  suite, and reuse its synthetic fixtures.

## Repository layout

Anything that concerns the whole application lives at the repository root:
`e2e/` because it will cover the UI as well as the API, `docs/` because it will
document both, and `bin/` for commands that work from any directory. Anything
belonging to one application lives in `frontend/` or `backend/`.

## Open decisions

- **Reaching the API in development:** a Vite proxy, which keeps one origin in
  the browser, or CORS on the backend. The `rack-cors` initializer is present
  but commented out.
- **API types:** generate TypeScript types from an API specification, or write
  them by hand and accept drift.
- **Data fetching and caching:** chosen when the frontend is connected to the
  API.
- **Visual style:** candidate themes live in `frontend/src/themes.ts` and are
  compared through a temporary in-app switcher; once one is chosen, the file
  collapses to a single theme and the switcher is removed.
- **Form generation:** a JSON Schema form library, or a renderer of our own over
  the component kit.
- **Run status updates:** polling, or push over Action Cable. Push would need a
  real cable adapter in development; the current `async` adapter only works
  because the job worker runs inside Puma.
- **Production:** how the built frontend is served alongside the API.
