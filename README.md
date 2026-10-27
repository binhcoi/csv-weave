# CSVWeave

**Reusable CSV formats, validation rules, and transformation maps.**

CSVWeave is a Ruby on Rails backend for configurable CSV conversion. Define the columns and validation rules for each file format, then map source values into the output fields you need. Formats and maps are saved through the API and reused across conversions.

The project brings together field validation, text formatting, precise numeric calculations, and date conversion in one configurable operation library.

## Example: customer import

A customer export needs a full name, a sortable name, an ISO date, and two representations of the phone number. A saved map defines how to build those fields from the source format.

**Source rows**

| given_name | family_name | joined_on | phone | internal_note |
| --- | --- | --- | --- | --- |
| Alex | Morgan | 12 Apr 2026 | +1-415-555-0132 | Legacy import |
| Sam | Rivera | 03 May 2026 | +1-212-555-0478 | Partner upload |
| Jordan | Lee | 28 Jun 2026 | +1-206-555-0926 | Manual entry |

**Transformation map**

Each rule fills one destination column. Source columns can be combined, reused, or omitted, and optional output fields can remain blank.

| Source | Instruction | Destination |
| --- | --- | --- |
| `given_name`, `family_name` | Join with a space. | `full_name` |
| `family_name`, `given_name` | Join with a comma and space. | `sort_name` |
| `joined_on` | Parse the date and write it as `YYYY-MM-DD`. | `joined_date` |
| `phone` | Copy the full value. | `phone` |
| `phone` | Take 4 characters starting at zero-based index 11. | `phone_last4` |
| `internal_note` | Omit this source field. | None |
| None | Leave this optional destination column blank. | `note` |

The phone values in this example are 15 characters long; index 11 selects the start of the final four digits.

**Destination rows**

The expected output is shown below. Empty cells represent blank CSV fields.

| full_name | sort_name | joined_date | phone | phone_last4 | note |
| --- | --- | --- | --- | --- | --- |
| Alex Morgan | Morgan, Alex | 2026-04-12 | +1-415-555-0132 | 0132 | |
| Sam Rivera | Rivera, Sam | 2026-05-03 | +1-212-555-0478 | 0478 | |
| Jordan Lee | Lee, Jordan | 2026-06-28 | +1-206-555-0926 | 0926 | |

Validation rules apply to both sides of the map. An input rule can require a name or check the source date format. An output rule can limit the length of the assembled name or check the reformatted date. The same source definition can be reused for another destination by creating another map.

## Capabilities

| Capability | What you can define |
| --- | --- |
| Reusable file formats | Named columns, output order, and validation rules shared by multiple maps. |
| Input and output validation | Required values, length limits, regex patterns, numeric ranges, date formats and ranges, and comparisons between columns in the same row. |
| Text transformations | Copy values, concatenate fields, extract substrings, truncate text, and build strings with named placeholders. |
| Numeric parsing | Parse base-10 integers and precise decimals, including exponent notation for decimal values. |
| Date conversion | Read a specified date format and write another, such as `12 Apr 2026` to `2026-04-12` or `04/12/2026`. |
| Arithmetic | Add, subtract, multiply, or divide two source values. Decimal calculations preserve precision; division has an explicit rounding scale. |
| Configuration checks | Validate operation settings, source references, and output-column ownership when saving rules. |
| Configuration API | Discover operations through catalogs, create formats and maps with nested rules, and edit groups of records atomically. |

For example, a sales map can multiply `unit_price` by `quantity` to produce a line total, while an output rule checks its permitted range. Decimal arithmetic keeps calculations such as `0.1 + 0.2` exact, producing `0.3`.

See the [validator guide](docs/validator.md) and [transformer guide](docs/transformer.md) for settings and examples.

## Design

The Rails API stores file types, columns, validation rules, and transformation maps in PostgreSQL. Catalogs expose the available operations and their settings schemas. Each configured rule selects a Ruby processor; the same operation can be reused with different settings across columns and maps.

The conversion flow is designed around five steps:

1. Read a source CSV row by header name.
2. Validate its values against the input format's rules.
3. Apply the map's transformations to build an output row.
4. Validate the result against the output format's rules.
5. Write accepted rows in output-column order and report rejected rows with their source row number, column, operation, and reason.

Rejected rows are skipped and reported while processing continues with subsequent rows.

**Development status:** The configuration API and all documented processors are implemented. CSV file upload and the conversion endpoint are still in development.

## Run locally

**Stack:** Ruby 3.3.7 · Rails 8.1 · PostgreSQL 17 · RSpec

Install Ruby 3.3.7, Bundler 4.0.11, PostgreSQL 17, a C build toolchain, and PostgreSQL client development headers. Your PostgreSQL role must be able to create development and test databases.

From the repository root:

```sh
gem install bundler -v 4.0.11
bundle install

export DB_HOST=127.0.0.1
export DB_USER=postgres
export DB_PASSWORD=postgres

bin/rails db:prepare
bin/rails server
```

Replace the sample PostgreSQL credentials with your local values. The API runs at `http://localhost:3000`; `GET /up` is its health endpoint. On a fresh installation, `db:prepare` initializes the database and seeds the supported operations. Run `bin/rails db:seed` to refresh those definitions later without duplicating them.

Database configuration is in [config/database.yml](config/database.yml). Development and tests use separate databases.

## Try the configuration API

With the server running, open another terminal. List the available transformation operations and their settings:

```sh
curl --fail-with-body -sS http://localhost:3000/column_transformers
```

Create a reusable file type with an email column:

```sh
curl --fail-with-body -sS http://localhost:3000/file_types \
  -H 'Content-Type: application/json' \
  --data '{"file_type":{"name":"Customer import","columns":[{"name":"email","position":0}]}}'
```

The response includes the new file-type ID. Retrieve the saved definitions, including their columns:

```sh
curl --fail-with-body -sS http://localhost:3000/file_types
```

Continue with the [API setup sequence](docs/api.md#integration-order) to attach validation rules, create an output format, and save a transformation map. The [validator guide](docs/validator.md) and [transformer guide](docs/transformer.md) describe the supported operations. [Rule configuration schemas](docs/input_schemas.md) explains how their settings are checked.

## Development

### Tests and quality checks

```sh
RAILS_ENV=test bin/rails db:test:prepare
CI=true RAILS_ENV=test bundle exec rspec
bin/rubocop
RAILS_ENV=test bin/rails zeitwerk:check
```

The [spec suite](spec) covers configuration rules, processor behavior, API contracts, and composition of saved rules on real CSV rows. Specs create their own operation catalogs; do not seed the test database separately.

[GitHub Actions](.github/workflows/ci.yml) runs the same test and style checks, checks autoloading, and scans with Brakeman and Bundler Audit.

### Ruby processor interface

Processors receive a configured `Validation` or `Transformation` record and work with `CSV::Row` values. Validators implement `validate(row)` and return `true` or `false` without changing the row. Transformers implement `transform(source, destination)`, write the target field, and return `nil` on success or an error message on failure. Expected failures clear the target to `nil` and preserve other fields.

`BaseValidator`, `BaseTransformer`, and `SingleSourceTransformer` provide shared behavior and are not catalog operations. Transformers report source names through `source_column_names` so referenced columns are protected from deletion. See [app/processors](app/processors) for the implementations and [rule configuration schemas](docs/input_schemas.md) for settings validation.
