# Rule configuration schemas

Each catalog operation has an `input_schema` describing its accepted JSON
settings. A validation or transformation rule supplies those settings in
`input_json`. These schemas validate operation configuration, such as source
column names and length limits. They do not describe the contents of a CSV file.

See [validators](validator.md) and [transformers](transformer.md) for each
operation's settings and behavior. The [API reference](api.md) describes how to
submit rules and retrieve catalog schemas.

## Defaults and null values

| Value | Meaning |
| --- | --- |
| Omitted `input_json` on create | Defaults to `{}`. The rule must still satisfy its schema and configuration checks. |
| Explicit `input_json: null` | Preserved if allowed by the selected schema and processor configuration checks. |
| Catalog `input_schema: null` | Skips JSON Schema validation. Processor configuration checks still run. |
| Catalog `input_schema: {}` | Accepts any JSON value, including null; processor configuration checks still run. |

`RequiredValidator` has a null schema and reads no settings. Parameterized
processors currently require objects, so they reject null, arrays, and scalar
settings. Omitted settings can also fail when an operation requires parameters.

## Schema checks and configuration checks

For example, copy, integer parse, and decimal parse use this schema:

```json
{
  "type": "object",
  "properties": {
    "source_column": { "type": "string", "minLength": 1 }
  },
  "required": ["source_column"],
  "additionalProperties": false
}
```

It accepts `{"source_column": "email"}` and rejects missing, empty, or non-string
source names and unexpected properties. The processor separately checks that
`email` exists in the map's input file type.

Saving a rule first checks its settings against the catalog schema, then checks
conditions such as bound ordering, regex syntax, and source-column existence.
These checks validate configuration without processing CSV values.

Configuration failures identify `input_json` in the API response's `errors`
object. See [API errors](api.md#errors) for response examples.

## Maintaining operation schemas

Catalog schemas use JSON Schema through `json_schemer` and are maintained in
[db/seeds.rb](../db/seeds.rb). Catalogs are read-only through the API.
After schema validation succeeds, the rule calls its processor's
`validate_configuration` hook for checks that depend on other settings or saved
records. Invalid schema documents are rejected on the catalog's `input_schema`
field; a rule that encounters an invalid catalog schema reports an `input_json`
error.
