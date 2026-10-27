# Validators

A validation rule selects a catalog operation and checks a column's value
without changing it. Rules can belong to input or output columns. Some
operations also compare another value in the same row. CSV conversion
execution is planned.

Every JSON example below is an **`input_json` settings object**, placed inside
a validation request. See [rule configuration schemas](input_schemas.md) for
settings validation and the [API reference](api.md#validation-rules) for a
complete request. Validators with settings reject unrecognized setting names.

## RequiredValidator

No settings are needed; omit `input_json` or use `{}`. Its catalog has no schema,
so other JSON values, including null, are accepted but ignored.

Rejects missing, null, empty, and whitespace-only fields. Zero is nonblank.

## LengthValidator

```json
{ "min": 2, "max": 100 }
```

Bounds are inclusive nonnegative integers. At least one is required; when both
are present, `min <= max`.

Counts characters, including whitespace, rather than bytes. Missing, null, and
empty fields have length zero. It checks text length; numeric outputs should
use numeric validation.

## RegexValidator

```json
{ "pattern": "\\A[A-Z]{2}-[0-9]{4}\\z" }
```

Requires a Ruby regex pattern string; an empty pattern is allowed. Invalid
syntax is rejected when saving the rule.

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
present, `min <= max`. Negative and fractional bounds are allowed. String and
null bounds are rejected.

Nonblank values must parse as finite decimals within the range. Parsing uses
`BigDecimal` and accepts signs, surrounding whitespace, and exponent notation.
Malformed or partially numeric values, `NaN`, and infinities fail. Parsed integer
and `BigDecimal` output values are also supported.

CSV values are compared without conversion through `Float`. Fractional bounds
have the precision of the configuration's JSON-number decoding. Missing, null,
empty, and whitespace-only fields pass; add a required rule to reject them.

## DateValidator

```json
{ "format": "%d/%m/%Y", "min": "2020-01-01", "max": "2030-12-31" }
```

Requires a Ruby `strptime` format describing a complete calendar, ordinal, or
ISO week date. Examples include `%Y-%m-%d`, `%d/%m/%Y`, `%d %b %Y`, `%Y-%j`, and
`%G-W%V-%u`. Formats missing date components are rejected when saving the rule.

Values must be real Gregorian dates and match the format exactly, including
padding and month-name case. Extra text or whitespace fails unless part of the
format. A parsed date must format back to the original value.

Optional `min` and `max` are inclusive dates in `YYYY-MM-DD`, regardless of the
value's format. Either, both, or neither may be supplied; when both are present,
`min <= max`. Invalid bounds are rejected.

Missing, null, empty, and whitespace-only fields pass; add a required rule to
reject them. The row value is never changed or reformatted.

## Same-row comparisons

`StringComparisonValidator` and `NumericComparisonValidator` compare the rule's
column on the left with `other_column` on the right. Both use these settings:

```json
{ "other_column": "maximum_amount", "operator": "<=" }
```

Both keys are required. `other_column` must be a nonempty string naming a column
in the same file type. Define both columns before attaching the rule. Operators
are `==`, `!=`, `<`, `<=`, `>`, and `>=`.

### StringComparisonValidator

Uses case-sensitive lexicographic ordering: `"apple" < "pear"`, `"Apple" < "apple"`,
and `"10" < "2"`. Nonblank values are converted to strings without trimming.
Missing, null, empty, and whitespace-only fields compare as `""`.

### NumericComparisonValidator

Uses finite `BigDecimal` values, so `"2" < "10"` and `"2.00" == "2"`. Signs,
surrounding whitespace, and exponent notation are accepted. Missing, null,
empty, and whitespace-only fields compare as zero. Other invalid numeric values
make every comparison fail, including `!=`.

These validators compare blank values rather than skipping them. Normalization
affects comparison only; neither validator changes the row.
