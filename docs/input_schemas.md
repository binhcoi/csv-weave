# Input schemas

`ColumnValidator.input_schema` and `ColumnTransformer.input_schema` describe the
parameters accepted by a processor. They use standard JSON Schema, validated by
the `json_schemer` gem. Schemas are maintained in `db/seeds.rb`.

A `nil` schema skips JSON Schema validation. `RequiredValidator` uses this because
it needs no parameters. Its `Validation` can omit `input_json` or supply `nil`.
Omitted parameters still default to `{}` in the database.

`CopyTransformer` requires a source column name:

```json
{
  "type": "object",
  "properties": {
    "name": { "type": "string", "minLength": 1 }
  },
  "required": ["name"],
  "additionalProperties": false
}
```

This accepts `{"name": "email"}`. It rejects missing, empty, or non-string names,
unexpected properties, and non-object parameters.

When a schema is present, `Validation` and `Transformation` validate `input_json`
before saving. Failures appear in `errors[:input_json]`, including the affected
field. Invalid schema documents appear in the catalog's `errors[:input_schema]`.
These checks are implemented in `app/validators`.

An explicit empty schema `{}` accepts any JSON value. Use `nil` when a processor
does not need a schema.
