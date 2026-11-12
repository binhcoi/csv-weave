# UI approach

## Decision

**React + TypeScript on Vite**, in a `frontend/` folder beside a `backend/`
folder, both running in one development container.

Chosen because the two configuration editors — nested columns, validations, and
per-operation parameters — are state-heavy client work, and because mature
component kits and list virtualization answer the "modern, easy to use, handles
large data" requirements as dependencies rather than as project work. The
backend stays API-only and unchanged in character.

Accepted costs: a second language, toolchain, lockfile, linter, and
security-advisory stream; an assembled rather than prescribed stack; no enforced
API/TypeScript contract; and a container that carries both Ruby and Node.

### Requirements this must serve

1. Web app UI.
2. Responsive; actions register quickly.
3. No needless jumping, forced reloads, or janky interactions.
4. Handles large data sets if needed.
5. Catalog `input_schema` drives the rule forms.
6. Backend changes to accommodate the UI are acceptable.
7. Looks modern.
8. Easy to use.

## Phase 1 scope — foundation

**Goal:** one container running both applications on two published ports, with a
bare-bones frontend welcome page that does not call the API, the backend
unchanged, e2e still covering the backend API fully, and every test suite
runnable from inside the container.

**In scope**

1. Restructure the repo into `frontend/` and `backend/`.
2. Scaffold the frontend: Vite, React, TypeScript, Vitest, ESLint, Prettier, and
   a single welcome page.
3. Add Node to the development image; publish a second port; run both processes.
4. Keep `bin/rails e2e:newman` working against the backend API.
5. Provide a way to run backend specs, frontend unit tests, and the e2e
   collection from inside the container.
6. Update CI for the new layout plus a frontend job.
7. Update `README.md`, `dev_note.md`, and `ROADMAP.md`.

**Explicitly out of scope** — these belong to later roadmap sections:

- Any API client, server-state library, router, or component kit.
- Backend changes for the UI (transactional configuration save, column reorder
  endpoint, enriched catalog schemas, pagination, CSV preview, paged error
  reports).
- Browser end-to-end tests.
- Production build and serving.

## Layout rule

**Anything scoped to the full app stays at the repo root.** `e2e/` stays at root
because it will grow UI tests and its generated fixtures are reusable for UI
end-to-end testing. `docs/` stays at root because it will grow frontend
documentation. Root also holds convenience wrappers so no command requires
changing directory first.

## Open decisions

- Whether a typed API contract (a spec generating frontend types) is in scope
  later, or hand-written types and accepted drift are good enough.
- How the production build is served.

## Root wrappers

Every routine task runs from the repo root, delegating into the right tree:
`bin/setup`, `bin/dev`, `bin/test [backend|frontend|e2e]`, `bin/lint`,
`bin/rails`, and `bin/ui` (npm in `frontend/`). The existing `backend/bin/*`
scripts stay as they are. Setting `BUNDLE_GEMFILE` in the image lets `bundle`
work from any directory.

## Ports

`.env` carries `API_PORT` and `UI_PORT`, both published by the single container.
This worktree (oak) uses 3501 and 4501; elm uses 3502 and 4502. `APP_PORT` is
renamed to `API_PORT`, which also appears in `docs/api.md` and `e2e/README.md`.

## Notes for going ahead

- The bind mount shadows any `node_modules` baked into the image, so dependency
  install is a first-run step inside the container, beside `bin/rails
  db:prepare`.
- `bin/dev` is currently `exec rails server`; two processes need a process
  manager and a root-level entry point.
- With `e2e/` at the root, the backend `Rakefile`'s task glob needs to reach up
  one level, and `e2e.rake`'s seeder require should resolve through `__dir__`
  instead of `Rails.root`. Its other paths already use `__dir__` and survive the
  move unchanged.
- The `Dockerfile.dev` `e2e` target installs Debian Bookworm's `nodejs`
  (Node 18), too old for current Vite. Once the base image carries a current
  Node, that target only needs Newman.
- There is no `.dockerignore`; the build context currently includes `log/`
  (179 MB) and `tmp/` (50 MB).
- `config/cable.yml` uses the in-process `async` adapter in development, which
  works only because `SOLID_QUEUE_IN_PUMA=1` runs the worker inside Puma.
  Relevant only if websocket push is adopted later.
- Restarting the container to pick up a new job class also restarts Vite, losing
  hot-reload state. Accepted cost of the single-container layout.
