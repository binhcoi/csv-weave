# CSVWeave

CSVWeave is a Ruby on Rails application for converting CSV data between defined formats. Users can configure source and destination schemas, attach validation rules to their columns, and define transformations between them. CSVWeave processes records according to those configurations, producing a converted CSV and reporting rows that fail validation.

See the [roadmap](ROADMAP.md) for current development status and planned work.

## Example

Suppose a supplier exports order data like this:

```csv
order_ref,first,last,ordered_on,product_code,qty,unit_price
A1001,Alex,Morgan,12 Apr 2026,SKU-0042,2,19.95
A1002,Sam,Rivera,03 May 2026,SKU-0107,3,4.50
A1003,Jordan,Lee,31 Feb 2026,SKU-0005,1,8.00
A1004,Taylor,Kim,28 Jun 2026,SKU-0030,0,12.00
```

The destination system expects a different schema. A saved map describes the conversion:

| Destination field | Transformation |
| --- | --- |
| `order_id` | Copy `order_ref` |
| `customer_name` | Join `first` and `last` with a space |
| `order_date` | Parse `ordered_on` and format as `YYYY-MM-DD` |
| `sku` | Extract the code after `SKU-` |
| `quantity` | Parse `qty` as an integer |
| `line_total` | Multiply `qty` by `unit_price` using decimal arithmetic |

Validation rules belong to the file types, not the map. For example, the supplier format can require a valid source date and an `SKU-` code, while the destination format can require a positive quantity and a nonnegative total.

**Resulting CSV**

```csv
order_id,customer_name,order_date,sku,quantity,line_total
A1001,Alex Morgan,2026-04-12,0042,2,39.9
A1002,Sam Rivera,2026-05-03,0107,3,13.5
```

**Rejected rows**

| Source line | Field | Reason |
| --- | --- | --- |
| 4 | `ordered_on` | Invalid date: `31 Feb 2026` |
| 5 | `quantity` | Must be at least 1 |

Valid rows are included in the output; invalid rows are skipped and reported. Another supplier with different column names or date formats can have its own map into the **same destination file type**, reusing its output validation rules.

## How it works

```text
Input CSV
    │
    ▼
Input file type ── column validation rules
    │
    ▼
Transformation map ── configured field processors
    │
    ▼
Output file type ── column validation rules
    │
    ├──► Output CSV (valid rows)
    └──► Error report (rejected rows)
```

Three reusable resources form the configuration:

- **File type:** A named CSV schema with ordered columns and optional per-column validation rules. It can be referenced by any number of maps.
- **Validation:** A rule attached to a file-type column, using a validator from the operation catalog with user-supplied parameters. Rules can also compare columns in the same row.
- **Transformation map:** A connection between an input and an output file type. Each transformation targets one output column and uses a transformer from the operation catalog, optionally reading multiple source columns.

Configurations are stored in PostgreSQL and managed through a REST API. Changing a mapping does not require changing a processor implementation.

### Extending the operations

Validators and transformers are plain Ruby classes under [`backend/app/processors/`](backend/app/processors). The database catalogs describe the available operations and their configuration schemas. An explicit allowlist controls which processor classes those catalog entries may resolve to.

The initial operation set covers required fields, string and numeric validation, regular expressions, date validation, same-row comparisons, copying, concatenation, formatting, substrings, date and number parsing, and arithmetic. Operation parameters are checked against JSON Schema and processor-specific configuration rules when configurations are saved.

See [Validator reference](docs/validator.md), [Transformer reference](docs/transformer.md), and [Configuration schemas](docs/input_schemas.md) for supported settings and examples.

## Repository layout

| Path | Contents |
| --- | --- |
| `backend/` | The Rails API application. |
| `e2e/` | End-to-end suite: fixtures, seeding tasks, and the Postman collection. Covers the whole app. |
| `docs/` | Reference documentation. |
| `bin/` | Convenience wrappers that run from anywhere in the repository. |

Anything scoped to the whole application lives at the repository root; anything
belonging to one application lives in its folder.

The wrappers mean no command needs a particular working directory:

| Command | Does |
| --- | --- |
| `bin/setup` | Install dependencies and prepare the database. Safe to re-run. |
| `bin/dev` | Start the development server. |
| `bin/test` | Run every suite. `bin/test backend` or `bin/test e2e` runs one. |
| `bin/lint` | Run linters. |
| `bin/rails` | Run a Rails command in `backend/`. |
| `bin/e2e` | `seed`, `clean`, or `newman`. |

## Run locally

Requires Ruby 4.0.9, PostgreSQL, and Bundler 4.0.11.

```bash
gem install bundler -v 4.0.11

# Set these to match your local PostgreSQL instance.
export DB_HOST=127.0.0.1
export DB_USER=postgres
export DB_PASSWORD=postgres

bin/setup
SOLID_QUEUE_IN_PUMA=1 bin/dev
```

The configuration API runs at `http://localhost:3000`. Database preparation seeds the catalogs of supported validators and transformers and creates the Solid Queue database. `SOLID_QUEUE_IN_PUMA=1` runs the background worker for validation and conversion runs inside the server.

You can inspect the available operations:

```bash
curl -sS http://localhost:3000/column_validators
curl -sS http://localhost:3000/column_transformers
```

And define a CSV format:

```bash
curl --fail-with-body -sS http://localhost:3000/file_types \
  -H 'Content-Type: application/json' \
  --data '{"file_type":{"name":"Partner customers","columns":[{"name":"given_name","position":0},{"name":"family_name","position":1}]}}'
```

The [API reference](docs/api.md) covers attaching validation rules, creating destination formats, defining transformations, updating saved configurations, and validating or converting uploaded files.

## Development

Run tests and quality checks with:

```bash
bin/test          # every suite
bin/test backend  # RSpec, preparing the test database first
bin/lint
```

RSpec covers models, configuration APIs, individual processors, composition of saved processing rules, the background validation and conversion runs, and end-to-end API flows using the e2e fixtures. GitHub Actions also runs linting, autoloading checks, and security scans.

End-to-end testing uses clearly fake `E2E-TEST` data. See [e2e/README.md](e2e/README.md) for fixtures, Postman, and Newman.

```bash
bin/e2e seed     # create the E2E-TEST configuration
bin/e2e clean    # delete all E2E-TEST records and files
bin/e2e newman   # run the Postman collection (image built with --target e2e)
```

## License

Licensed under the [MIT License](LICENSE).
