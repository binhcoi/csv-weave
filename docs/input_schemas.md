# Input schemas

Catalog entries store an `input_schema` describing the JSON settings accepted by
a processor. A rule stores those settings in `input_json`. Schemas use JSON
Schema through `json_schemer` and are maintained in [db/seeds.rb](../db/seeds.rb).

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

Before saving a `Validation` or `Transformation`, the model checks `input_json`
against its catalog schema. If the record has no errors, the processor's
`validate_configuration` hook checks constraints such as bound ordering, regex
syntax, or source-column existence. These checks validate configuration; they
do not process CSV values.

Schema and processor configuration failures appear in `errors[:input_json]`.
Invalid schema documents are rejected on the catalog's `input_schema` field.
If an invalid catalog schema reaches a rule, the rule reports an `input_json`
error instead of processing it. API error response shapes are documented in
[API errors](api.md#errors).
