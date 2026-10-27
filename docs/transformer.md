# Transformers

A `Transformation` selects a catalog operation and an output column within a
map. `transform(source, destination)` reads from a source `CSV::Row`, writes the
target field in the destination row, and returns `nil` on success or an error
message string for an expected failure. Expected failures clear the target to
`nil`. The source and other destination fields are preserved.

The conversion API that coordinates these calls and collects their errors is
still planned. See the [API reference](api.md#transformation-rules) for creating
rules and [input schemas](input_schemas.md) for configuration validation.

## Single-source settings

Copy, integer parse, and decimal parse accept the same `input_json`:

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

## ConcatenateTransformer

```json
{
  "source_columns": ["given_name", "family_name"],
  "separator": " "
}
```

`source_columns` is a required, nonempty array of nonempty column-name strings
from the map's input file type. Values are joined in this order, including any
repeated source names. One source is allowed. `separator` is an optional string
defaulting to `""`; additional settings are rejected.

Missing CSV fields, null, empty, and whitespace-only values are skipped, so
`["Alex", null, "Morgan"]` joined with a space becomes `"Alex Morgan"`. Nonblank
values are not trimmed. If every value is blank, the result is `""` without an
error; output validators decide whether that is acceptable.

Every configured source must exist. A missing configured source prevents saving
the rule; at runtime it clears the target and returns an error. All source names
are reported to the existing column-deletion guard.

## SubstringTransformer

```json
{
  "source_column": "product_code",
  "start": 2,
  "length": 4
}
```

Extracts up to `length` characters starting at the zero-based `start` position;
`"AB1234XY"` with these settings becomes `"1234"`. Both settings are required
nonnegative integers. Negative offsets and additional settings are rejected.
The source uses the same lookup and deletion protection as the other
single-source transformers.

Positions count Ruby string characters, not bytes or visual grapheme clusters.
Whitespace, punctuation, and newlines are preserved. A length extending past
the end returns the remaining text. A zero length or start at or beyond the end
returns `""`. Missing CSV headers and null values write `nil` without an error;
empty strings remain `""`. Output validators determine whether a blank result
is acceptable.

## TruncateTransformer

```json
{
  "source_column": "description",
  "length": 20
}
```

Keeps up to `length` characters from the start of the source value, with no
ellipsis or other suffix. `length` is a required nonnegative integer; zero
produces `""` for any non-null value. Values at or below the limit are unchanged.
Additional settings are rejected. The source uses the same lookup and deletion
protection as the other single-source transformers.

Length counts Ruby string characters, not bytes or visual grapheme clusters,
matching substring. Whitespace, punctuation, and newlines count toward the
limit and are preserved. Missing CSV headers and null values write `nil`
without an error; empty strings remain `""`. Output validators determine
whether a blank result is acceptable.

## DateParseTransformer

```json
{
  "source_column": "joined_on",
  "format": "%d/%m/%Y",
  "output_format": "%m/%d/%Y"
}
```

Parses a date using the required Ruby `strptime` input `format` and writes text
using the optional Ruby `strftime` `output_format`. With these settings,
`"29/02/2024"` becomes `"02/29/2024"`. Omitting `output_format` defaults to
`%Y-%m-%d` (ISO `YYYY-MM-DD`). An explicit output format must be a nonempty
string; partial formats such as `%Y-%m` and literal punctuation are allowed.
The source uses the same lookup and deletion protection as the other
single-source transformers. Additional settings are rejected.

The format must describe a complete calendar, ordinal, or ISO week date, using
the same strict parser as `DateValidator`. Examples include `%Y-%m-%d`,
`%d/%m/%Y`, `%d %b %Y`, `%Y-%j`, and `%G-W%V-%u`. Values must be real Gregorian
dates and match the format exactly, including padding and month-name case.
Surrounding whitespace and extra text fail unless part of the format.
Incomplete formats are rejected when saving the rule.

Missing CSV headers, null, empty, and whitespace-only fields write `nil`
without an error. Other invalid values clear the target and return an error
such as `source column "joined_on" contains an invalid date`. Output required
validation can reject blank results. For complete date output, configure an
output date validator with the same format as `output_format`.
