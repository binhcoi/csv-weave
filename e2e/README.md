# End-to-end testing

Everything for end-to-end testing lives in this folder, except the RSpec specs in
[`spec/e2e/`](../spec/e2e). All generated data is clearly fake: configuration names start
with `E2E-TEST`, uploaded files with `e2e_test_`, order refs look like `TEST-1001`, SKUs like
`SKU-T042`, and names like `Testa Fakeworth`.

```text
e2e/
  fixtures/                 # input CSVs
    expected/               # expected outputs and error reports for each fixture
  support/
    configuration_seeder.rb # creates the E2E-TEST file types, validations, and map
  tasks/e2e.rake            # e2e:seed, e2e:clean, e2e:newman
  postman/
    CSVWeave.postman_collection.json
    environments/local.postman_environment.json
  reports/                  # Newman reports (gitignored)
```

## Fixtures

| File | Purpose | Conversion | Validation |
| --- | --- | --- | --- |
| `e2e_test_orders_valid.csv` | 5 clean rows, one quoted name containing a comma | 5 accepted | 5 accepted |
| `e2e_test_orders_mixed.csv` | 2 good rows, plus one failure per stage | 2 accepted, 6 rejected, 7 errors | 4 accepted, 4 rejected |
| `e2e_test_orders_bad_header.csv` | `unit_price` header missing | file rejected | file rejected |
| `e2e_test_orders_latin1.csv` | ISO-8859-1 bytes instead of UTF-8 | file rejected | file rejected |

`spec/e2e/configuration_seeder_spec.rb` checks that each fixture still produces the files in
`expected/`. If you change a fixture or a seeded rule, update the expected files too.

## Rake tasks

Run tasks inside the worktree's own container. The tasks refuse to run in production.

| Task | What it does |
| --- | --- |
| `bin/rails e2e:seed` | Creates the E2E-TEST configuration (idempotent) and prints its IDs. Requires the catalogs (`bin/rails db:seed`). |
| `bin/rails e2e:clean` | Deletes every `E2E-TEST` file type and map, plus their data files, runs, and stored files. |
| `bin/rails e2e:newman` | Runs the Postman collection against `http://localhost:3000` (this container's server) and writes `reports/newman.xml`. |

Use the development environment (the container default). The test database belongs to RSpec;
leftover E2E-TEST rows there make the suite fail.

## RSpec

```bash
CI=true RAILS_ENV=test bundle exec rspec spec/e2e              # about 2 seconds
CI=true RAILS_ENV=test E2E_SLOW=1 bundle exec rspec spec/e2e   # adds the 3000-row case
```

## Postman and Newman

The collection creates its own configuration through the API (named
`E2E-TEST Postman ... <timestamp>`), so it doesn't need `e2e:seed`. It needs a running server
and Solid Queue worker (`SOLID_QUEUE_IN_PUMA=1`) and the seeded catalogs.

| Folder | What it does |
| --- | --- |
| `00 Setup` | Reads the catalogs, creates the input and output file types with their validations, reads output column IDs, and creates the map. |
| `01 Upload` | Uploads the four fixture CSVs. |
| `02 Validate` | Validates the valid, mixed, and Latin-1 uploads; polls each run; checks counts and error reports. |
| `03 Convert` | Converts the valid, mixed, and bad-header uploads; polls; checks the output CSV and error reports. |
| `04 Edge cases` | Run reuse (200, same run), file-type mismatch (422), unknown data file (404), unknown map (422). |

Requests save IDs into collection variables, so run the folders in order. Polling requests
repeat themselves until the run finishes, which only works in the Collection Runner or Newman.

**Newman (command line):** requires the image built with the `e2e` target
(`docker build -f Dockerfile.dev --target e2e ...`). The default target has no Node or Newman.

```bash
docker exec <container> bin/rails e2e:newman
```

**Postman app:**

1. Import `postman/CSVWeave.postman_collection.json` and `postman/environments/local.postman_environment.json`.
2. In the environment, set `baseUrl` to `http://localhost:<APP_PORT>` from the worktree's `.env`.
3. In Postman settings, set the working directory to this repository's `e2e/fixtures` folder so the uploads find their files.
4. Run the collection with the Collection Runner.

Afterwards, `bin/rails e2e:clean` removes everything the collection created.
