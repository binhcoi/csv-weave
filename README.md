# CSVWeave

**A configurable CSV conversion engine built with Ruby on Rails.**

CSVWeave brings file formats, validation rules, and field transformations into reusable definitions. Describe the data you receive, describe the data you need, and save a map between them. The project is designed to turn those definitions into repeatable conversions with an output CSV and a structured error report.

**Work in progress:** Format and mapping configuration, column validators, and copy, integer parse, decimal parse, concatenate, substring, truncate, date parse, format-string, and arithmetic transformers are implemented. CSV conversion execution is planned.

## The workflow

This example illustrates the planned conversion of three rows of customer data.

**Source rows**

| given_name | family_name | joined_on | phone | internal_note |
| --- | --- | --- | --- | --- |
| Alex | Morgan | 12 Apr 2026 | +1-415-555-0132 | Legacy import |
| Sam | Rivera | 03 May 2026 | +1-212-555-0478 | Partner upload |
| Jordan | Lee | 28 Jun 2026 | +1-206-555-0926 | Manual entry |

**Transformation map**

The table below lists the transformations that build the destination rows, along with fields left unmapped. Each transformation fills one destination column using one or more source columns. Multiple transformations can read the same fields: the name fields produce two name formats, and `phone` supplies both the full number and its final four characters.

| Source | Instruction | Destination |
| --- | --- | --- |
| `given_name`, `family_name` | Join with a space. | `full_name` |
| `family_name`, `given_name` | Join with a comma and space. | `sort_name` |
| `joined_on` | Parse the date and write it as `YYYY-MM-DD`. | `joined_date` |
| `phone` | Copy the full value. | `phone` |
| `phone` | Extract the final four characters. | `phone_last4` |
| `internal_note` | Omit this source field. | None |
| None | Leave this optional destination column blank. | `note` |

**Destination rows**

Applying the map produces the following values. Empty cells represent blank CSV fields.

| full_name | sort_name | joined_date | phone | phone_last4 | note |
| --- | --- | --- | --- | --- | --- |
| Alex Morgan | Morgan, Alex | 2026-04-12 | +1-415-555-0132 | 0132 | |
| Sam Rivera | Rivera, Sam | 2026-05-03 | +1-212-555-0478 | 0478 | |
| Jordan Lee | Lee, Jordan | 2026-06-28 | +1-206-555-0926 | 0926 | |

## Design

| Component | Responsibility |
| --- | --- |
| **File formats** | Define ordered columns and the validation rules for each column. A format can be reused by multiple maps. |
| **Transformation maps** | Connect a source format to a destination format and hold the instructions for filling destination columns. |
| **Validators and transformers** | Implement checks and operations in Ruby. Catalog entries list the supported classes and describe the settings each accepts. |
| **Conversion engine - planned** | Read a CSV file and apply a saved map, coordinating validation, transformation, output, and error reporting. |

The same validator or transformer can be configured for different columns, formats, and maps. New operations extend the Ruby library and are exposed through the catalogs.

### Processing a file

The planned conversion engine will load the selected map and its file formats and rules. It will then process each row in order:

1. **Read:** Parse the next CSV row using the source headers.
2. **Validate input:** Check the original values against the source format's rules.
3. **Transform:** Apply the mapping to build a destination row.
4. **Validate output:** Check the generated values against the destination format's rules.
5. **Write:** Write accepted rows in destination column order, including blanks for unmapped optional columns.

A validation or transformation failure stops that row and reports its source row number, column, operation, and reason.

Output validation catches problems introduced by transformation. For example, joining two valid source names can produce a full name that exceeds the destination's length limit.

The [API reference](docs/api.md) covers endpoints and request/response contracts. The [validator guide](docs/validator.md) and [transformer guide](docs/transformer.md) describe operation settings and behavior. [Input schemas](docs/input_schemas.md) explains how configuration is validated.

## Development status

| Area | Status |
| --- | --- |
| File formats, column rules, reusable maps, and operation catalogs | Implemented, including nested creation and atomic bulk editing. |
| Required-value, length, regex, numeric range, date, and same-row comparison validators; copy, numeric parsing, concatenate, substring, truncate, date parse, format-string, and arithmetic transformers | Implemented with configuration and row-behavior coverage. |
| Streaming conversion, ordered output, and structured error reports | Planned. |
| All-or-nothing and valid-rows-only processing | Planned. |

The configuration foundation and planned operation library are implemented. Representative pipeline coverage remains before building the conversion engine.

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

## Tests and quality checks

```sh
RAILS_ENV=test bin/rails db:test:prepare
CI=true RAILS_ENV=test bundle exec rspec
bin/rubocop
RAILS_ENV=test bin/rails zeitwerk:check
```

The suite covers model and database constraints, processor behavior, operation schemas, and HTTP contracts. Failure-path coverage checks that an invalid bulk edit restores removed rules and discards earlier additions, that edits cannot remove another format's or map's records, and that dependency checks prevent destructive deletions.

Explore the [model specs](spec/models), [processor specs](spec/processors), and [request specs](spec/requests). Specs create their own operation catalogs; do not seed the test database separately.

[GitHub Actions](.github/workflows/ci.yml) is configured to run RSpec against PostgreSQL, check Ruby style and autoloading, and scan with Brakeman and Bundler Audit.
