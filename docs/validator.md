# Validators

A `Validation` attaches a catalog operation to a column. A processor's
`validate(row)` reads that column by header from a `CSV::Row` and returns `true`
or `false` without changing the row. Rules can belong to input or output columns.
The conversion API that coordinates these calls is still planned.

The examples below are `input_json` settings. See [input schemas](input_schemas.md)
for configuration validation and the [API reference](api.md#validation-rules)
for creating rules.

## RequiredValidator

No settings are needed; omit `input_json` or use `{}`. Its catalog has no schema,
so other JSON values, including null, are accepted but ignored.

Rejects missing, null, empty, and whitespace-only fields. Zero is nonblank.

## LengthValidator

```json
{ "min": 2, "max": 100 }
```

Bounds are inclusive nonnegative integers. At least one is required; when both
are present, `min <= max`. Additional settings are rejected.

Counts characters, including whitespace, rather than bytes. Missing, null, and
empty fields have length zero. It checks text length; numeric outputs should
use numeric validation.

## RegexValidator

```json
{ "pattern": "\\A[A-Z]{2}-[0-9]{4}\\z" }
```

Requires a Ruby regex pattern string; an empty pattern is allowed. Invalid
syntax is rejected when saving the rule. Additional settings are rejected.

Patterns can match substrings. Use `\A` and `\z` for the whole value, escaping
backslashes as shown when writing JSON. Nonblank values are matched without
trimming. Missing, null, empty, and whitespace-only fields pass; add a required
rule to reject them.

Each match has a fixed 50 ms timeout. A timeout returns `false`; the rule cannot
override the limit.

## NumericRangeValidator

```json
{ "min": -2.5, "max": 100 }
```

Bounds are inclusive JSON numbers. At least one is required; when both are
present, `min <= max`. Negative and fractional bounds are allowed. Strings,
null bounds, and additional settings are rejected.

Nonblank values must parse as finite decimals within the range. Parsing uses
`BigDecimal` and accepts signs, surrounding whitespace, and exponent notation.
Malformed or partially numeric values, `NaN`, and infinities fail. Parsed integer
and `BigDecimal` output values are also supported.

CSV values are compared without conversion through `Float`. Fractional bounds
have the precision of the configuration's JSON-number decoding. Missing, null,
empty, and whitespace-only fields pass; add a required rule to reject them.
