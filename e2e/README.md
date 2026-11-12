# End-to-end testing

Everything for end-to-end testing lives in this folder, except the RSpec specs in
[`backend/spec/e2e/`](../backend/spec/e2e). All generated data is clearly fake: configuration names start
with `E2E-TEST`, uploaded files with `e2e_test_`, IDs look like `TEST-1001` or `REG-T0001`,
and names like `Testa Fakeworth`.

```text
e2e/
  fixtures/
    basic/                  # supplier orders scenario CSVs
      expected/             # expected outputs and error reports for each fixture
    comprehensive/          # event registrations scenario CSVs
      expected/
  support/
    configuration_seeder.rb # creates the E2E-TEST file types, validations, and maps
  tasks/e2e.rake            # e2e:seed, e2e:clean, e2e:newman
  postman/
    generate_collection.py  # writes CSVWeave.postman_collection.json
    CSVWeave.postman_collection.json
    environments/local.postman_environment.json
  reports/                  # Newman reports (gitignored)
```

## Scenarios and fixtures

Two seeded scenarios, each with its own fixture folder:

- **basic** — supplier orders -> warehouse orders (the README example). Simple and readable.
- **comprehensive** — event registrations -> attendee badges. Uses every cataloged validator
  and transformer, all four arithmetic operators including division with `scale`, date bounds,
  same-row comparisons, the `%%` format escape, and an unmapped output column (`internal_ref`).

### basic (`fixtures/basic/`)

| File | Purpose | Conversion | Validation |
| --- | --- | --- | --- |
| `e2e_test_orders_valid.csv` | 5 clean rows, one quoted name containing a comma | 5 accepted | 5 accepted |
| `e2e_test_orders_mixed.csv` | 2 good rows, plus one failure per stage | 2 accepted, 6 rejected, 7 errors | 4 accepted, 4 rejected |
| `e2e_test_orders_bad_header.csv` | `unit_price` header missing | file rejected | file rejected |
| `e2e_test_orders_latin1.csv` | ISO-8859-1 bytes instead of UTF-8 | file rejected | file rejected |

### comprehensive (`fixtures/comprehensive/`)

| File | Purpose | Conversion | Validation |
| --- | --- | --- | --- |
| `e2e_test_registrations_valid.csv` | 4 clean rows showing blank-column handling, exponent decimals, truncation, and division rounding | 4 accepted | 4 accepted |
| `e2e_test_registrations_mixed.csv` | 2 good rows, one failing row per rule across all three stages, and one row failing five input rules at once | 2 accepted, 15 rejected, 24 errors | 8 accepted, 9 rejected, 13 errors |

`backend/spec/e2e/configuration_seeder_spec.rb` checks that each fixture still produces the files in
its `expected/` folder. If you change a fixture or a seeded rule, update the expected files too.

## Rake tasks

Run tasks inside the worktree's own container. The tasks refuse to run in production.

| Task | What it does |
| --- | --- |
| `bin/e2e seed` | Creates both E2E-TEST scenario configurations (idempotent) and prints their IDs. Requires the catalogs (`bin/rails db:seed`). |
| `bin/e2e clean` | Deletes every `E2E-TEST` file type and map, plus their data files, runs, and stored files. |
| `bin/e2e newman` | Runs the Postman collection against `http://localhost:3000` (this container's server) and writes `reports/newman.xml`. `FOLDER=Basic` runs one folder. |

Use the development environment (the container default). The test database belongs to RSpec;
leftover E2E-TEST rows there make the suite fail.

## RSpec

The specs live in `backend/spec/e2e` and resolve this directory through `E2E_ROOT`,
defined in `backend/spec/rails_helper.rb`.

```bash
bin/test backend spec/e2e              # about 4 seconds
E2E_SLOW=1 bin/test backend spec/e2e   # adds the 3000-row case
```

## Postman and Newman

The collection creates its own configuration through the API (named
`E2E-TEST Postman ... <timestamp>`), so it doesn't need `e2e:seed`. It needs a running server
and Solid Queue worker (`SOLID_QUEUE_IN_PUMA=1`) and the seeded catalogs.

```text
CSVWeave E2E
  Basic/            00 Setup, 01 Upload, 02 Validate, 03 Convert
  Comprehensive/    00 Setup, 01 Upload, 02 Validate, 03 Convert
  Edge cases/       uses Basic's records; run Basic first
```

| Folder | What it does |
| --- | --- |
| `00 Setup` | Reads the catalogs, creates the input and output file types with their validations, reads output column IDs, and creates the map. |
| `01 Upload` | Uploads the scenario's fixture CSVs. |
| `02 Validate` | Validates uploads, polls each run, and checks counts, error line counts, and the stage of every error. |
| `03 Convert` | Converts uploads, polls, and checks the output header, row count, first row, and error reports. Rejected runs must have no output (404). |
| `Edge cases` | Run reuse (200, same run), file-type mismatch (422), unknown data file (404), unknown map (422). |

Expected values in the tests come from the files in `fixtures/*/expected/` at the time the
collection was generated; RSpec compares the full files byte for byte. Variables are prefixed
per scenario (`basic_`, `full_`) so the scenarios don't overwrite each other. Polling requests
repeat themselves until the run finishes, which only works in the Collection Runner or Newman.

**Regenerating the collection:** the JSON is generated by `postman/generate_collection.py`
(Python 3, standard library only). Run `python3 e2e/postman/generate_collection.py` after changing
a fixture, an expected file, or a scenario. The script's scenario definitions mirror
`support/configuration_seeder.rb`, so change both together. Hand edits to the JSON, including
exports from the Postman app, are overwritten on the next run.

**Newman (command line):** requires the image built with the `e2e` target
(`docker build -f Dockerfile.dev --target e2e ...`). The default target has no Node or Newman.

```bash
docker exec <container> bin/e2e newman                       # whole collection
docker exec <container> bin/e2e newman FOLDER=Comprehensive  # one folder
```

**Postman app:**

1. Import `postman/CSVWeave.postman_collection.json` and `postman/environments/local.postman_environment.json`.
2. In the environment, set `baseUrl` to `http://localhost:<API_PORT>` from the worktree's `.env`.
3. In Postman settings, set the working directory to this repository's `e2e/fixtures` folder so the uploads find their files.
4. Run the collection with the Collection Runner.

Afterwards, `bin/e2e clean` removes everything the collection created.
