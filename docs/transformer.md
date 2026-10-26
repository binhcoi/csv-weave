# Transformers

A `Transformation` selects a catalog operation and an output column within a
map. `transform(source, destination)` reads from a source `CSV::Row`, writes the
target field in the destination row, and returns `nil` on success or an error
message string for an expected failure. Expected failures clear the target to
`nil`. The source and other destination fields are preserved.

The conversion API that coordinates these calls and collects their errors is
still planned. See the [API reference](api.md#transformation-rules) for creating
rules and [input schemas](input_schemas.md) for configuration validation.

## Shared settings

All currently implemented transformers accept the same `input_json`:

```json
{ "source_column": "amount" }
```

`source_column` is a required, nonempty string identifying a column in the map's
input file type. Additional settings are rejected. The output column is selected
by the rule's `output_column_id`, not by `input_json`.

A nonexistent configured source column prevents saving the rule. If encountered
during transformation, it returns an error and clears the target. An existing
configured column with no matching CSV header supplies `nil` to the operation.

`SingleSourceTransformer` shares source lookup, configuration validation, and
source-reference reporting. It and `BaseTransformer` are abstract classes, not
catalog choices.

## CopyTransformer

Copies the source value unchanged, including whitespace, empty strings, and
`nil`. A missing CSV header therefore writes `nil` without an error.

## IntegerParseTransformer

Parses a base-10 integer using Ruby's `Integer`. Signs and surrounding whitespace
are accepted; `"0042"` becomes the integer `42`. Fractional, exponent, and
partially numeric text fail.

Missing, null, empty, and whitespace-only values write `nil` without an error.
Other invalid values clear the target and return an error such as
`source column "amount" contains an invalid integer`.

## DecimalParseTransformer

Parses a finite `BigDecimal`, preserving decimal precision without converting
through `Float`. Signs, surrounding whitespace, and exponent notation are
accepted; `"1.25e3"` becomes the decimal value `1250`. The destination holds a
`BigDecimal`, not a formatted string.

Missing, null, empty, and whitespace-only values write `nil` without an error.
Malformed or partially numeric text, `NaN`, and infinities clear the target and
return an error such as `source column "amount" contains an invalid decimal`.

For both numeric parsers, attach output validators to decide whether a blank
result is acceptable.
