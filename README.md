# CSVWeave

**A configurable CSV conversion engine built with Ruby on Rails.**

CSVWeave brings file formats, validation rules, and field transformations into reusable definitions. Describe the data you receive, describe the data you need, and save a map between them. The project is designed to turn those definitions into repeatable conversions with an output CSV and a structured error report.

**Work in progress:** Format and mapping configuration, required-value validation, and field copying are implemented. Additional processors and CSV conversion execution are planned.

## The workflow

This example illustrates the planned conversion of three rows of customer data.

**Source rows**

| customer_id | given_name | family_name | email | joined_on | credit_limit | phone | internal_note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C1042 | Alex | Morgan | alex@example.test | 12 Apr 2026 | 001250.50 | +1-415-555-0132 | Legacy import |
| C1043 | Sam | Rivera | sam@example.test | 03 May 2026 | 000050.00 | +1-212-555-0478 | Partner upload |
| C1044 | Jordan | Lee | jordan@example.test | 28 Jun 2026 | 000300.75 | +1-206-555-0926 | Manual entry |

**Transformation map**

The table below lists the transformations that build the destination rows, along with fields left unmapped. Each transformation fills one destination column using one or more source columns. Multiple transformations can read the same fields: the name fields produce two name formats, and `phone` supplies both the full number and its final four characters.

| Source | Instruction | Destination |
| --- | --- | --- |
| `customer_id` | Copy the value. | `external_id` |
| `given_name`, `family_name` | Join with a space. | `full_name` |
| `family_name`, `given_name` | Join with a comma and space. | `directory_name` |
| `email` | Copy the value. | `contact_email` |
| `joined_on` | Parse the date and write it as `YYYY-MM-DD`. | `joined_date` |
| `credit_limit` | Parse the numeric value. | `credit_limit` |
| `phone` | Copy the full value. | `contact_phone` |
| `phone` | Extract the final four characters. | `phone_last4` |
| `internal_note` | Omit this source field. | None |
| None | Leave this optional destination column blank. | `note` |

**Destination rows**

Applying the map produces the following values. Empty cells represent blank CSV fields.

| external_id | full_name | directory_name | contact_email | joined_date | credit_limit | contact_phone | phone_last4 | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1042 | Alex Morgan | Morgan, Alex | alex@example.test | 2026-04-12 | 1250.50 | +1-415-555-0132 | 0132 | |
| C1043 | Sam Rivera | Rivera, Sam | sam@example.test | 2026-05-03 | 50.00 | +1-212-555-0478 | 0478 | |
| C1044 | Jordan Lee | Lee, Jordan | jordan@example.test | 2026-06-28 | 300.75 | +1-206-555-0926 | 0926 | |

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

The [API reference](docs/api.md) covers configuring formats, rules, and maps. See [input schemas](docs/input_schemas.md) for operation parameters.

## Development status

| Area | Status |
| --- | --- |
| File formats, column rules, reusable maps, and operation catalogs | Implemented, including nested creation and atomic bulk editing. |
| Required-value validator and copy transformer | Implemented with configuration and row-behavior coverage. |
| Text, numeric, date, and cross-column operations | Planned. |
| Streaming conversion, ordered output, and structured error reports | Planned. |
| All-or-nothing and valid-rows-only processing | Planned. |

The configuration foundation is complete. Current work is extending the operation library before building the conversion pipeline.

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
