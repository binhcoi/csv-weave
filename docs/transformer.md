# Transformers

A transformation rule selects an operation and fills one output column within
a map. Each operation reads values from the map's input columns. The rule's
`output_column_id` selects the target column.

Every JSON example below is an **`input_json` settings object**, placed inside
a transformation request. See the [API reference](api.md#transformation-rules)
for a complete request and [rule configuration schemas](input_schemas.md) for
settings validation. CSV conversion execution is planned.

## Common rules

- Only the documented settings are accepted.
- Source names must be nonempty strings identifying columns in the map's input
  file type. All declared sources must exist before the rule can be saved.
  A configured source that no longer exists causes an error during transformation.
- Columns referenced by a transformation cannot be deleted.
- Source values and other output fields are preserved. An expected failure
  clears the target to null and returns an error message.
- Output validation rules check the produced values. Use a required rule when
  a blank result is unacceptable. Blank handling differs by operation below.

## Copy and numeric parse settings

Copy, integer parse, and decimal parse accept the same `input_json`:

```json
{ "source_column": "amount" }
```

`source_column` is required.

## CopyTransformer

Copies the source value unchanged, including whitespace, empty strings, and
null. A missing CSV header therefore writes null without an error.

## IntegerParseTransformer

Parses a base-10 integer using Ruby's `Integer`. Signs and surrounding whitespace
are accepted; `"0042"` becomes the integer `42`. Fractional, exponent, and
partially numeric text fail.

Missing, null, empty, and whitespace-only values write null without an error.

## DecimalParseTransformer

Parses a finite `BigDecimal`, preserving decimal precision without converting
through `Float`. Signs, surrounding whitespace, and exponent notation are
accepted; `"1.25e3"` becomes the decimal value `1250`. The destination holds a
`BigDecimal`, not a formatted string.

Missing, null, empty, and whitespace-only values write null without an error.
Malformed or partially numeric text, `NaN`, and infinities fail.

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
defaulting to `""`.

Missing CSV fields, null, empty, and whitespace-only values are skipped, so
`["Alex", null, "Morgan"]` joined with a space becomes `"Alex Morgan"`. Nonblank
values are not trimmed. If every value is blank, the result is `""` without an
error.

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
nonnegative integers. Negative offsets are rejected.

Positions count Ruby string characters, not bytes or visual grapheme clusters.
Whitespace, punctuation, and newlines are preserved. A length extending past
the end returns the remaining text. A zero length or start at or beyond the end
returns `""`. Missing CSV headers and null values write null without an error;
empty strings remain `""`.

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

Length counts Ruby string characters, not bytes or visual grapheme clusters,
matching substring. Whitespace, punctuation, and newlines count toward the
limit and are preserved. Missing CSV headers and null values write null
without an error; empty strings remain `""`.

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

The input `format` follows [DateValidator's exact date-matching rules](validator.md#datevalidator).
It must describe a complete calendar, ordinal, or ISO week date. Incomplete
formats are rejected when saving the rule.

Missing CSV headers, null, empty, and whitespace-only fields write null
without an error. Other invalid dates fail. For complete date output, configure
an output date validator with the same format as `output_format`.

## FormatStringTransformer

```json
{
  "source_columns": ["given_name", "family_name"],
  "format": "%{family_name}, %{given_name}"
}
```

Substitutes named source values into a string template. For `given_name = "Alex"`
and `family_name = "Morgan"`, these settings produce `"Morgan, Alex"`.

`source_columns` is a required, nonempty array of nonempty column-name strings
from the map's input file type. `format` is a required string, including `""`.
Repeated sources and placeholders are allowed; listed sources may be unused.

Use `%{column_name}` to substitute a listed source and `%%` for a literal percent.
Names match exactly, including spaces and Unicode; placeholder names cannot
contain braces. For example, `%%{given_name}` produces the literal
`%{given_name}`, while `%%%{given_name}` produces `%Alex`. Other directives such
as `%s`, `%d`, and `%<name>s`, malformed placeholders, and placeholders naming
unlisted sources are rejected when saving the rule. Templates and substituted
values are treated as text; inserted values are never interpreted again.

Missing CSV headers and null values become `""`; empty strings stay empty.
Whitespace and template punctuation are preserved, so a missing family name
with the example template produces `", Alex"`. No separator cleanup or blank
skipping is applied.

Every listed source must exist, including sources unused by the template.
Runtime missing-source or template errors fail the transformation.

## ArithmeticTransformer

```json
{
  "source_columns": ["subtotal", "tax"],
  "operator": "+"
}
```

Takes exactly two ordered source names and one operator: `+`, `-`, `*`, or `/`.
The first source is the left operand and the second is the right operand.
Repeated names are allowed, such as multiplying a column by itself.

Values parse as finite `BigDecimal` numbers, accepting signs, surrounding
whitespace, and exponent notation. Missing CSV headers, null, empty, and
whitespace-only values count as zero, matching numeric comparison. Malformed
numbers, `NaN`, and infinities fail.

Addition, subtraction, and multiplication produce exact `BigDecimal` results
without an implicit rounding step; `0.1 + 0.2` produces `0.3`.

Division additionally requires `scale`, an integer from 0 to 100:

```json
{
  "source_columns": ["total", "quantity"],
  "operator": "/",
  "scale": 2
}
```

Division rounds an exact ratio to that many decimal places using half-up
rounding. For example, `1 / 3` at scale 2 produces `0.33`, `1 / 8` produces
`0.13`, and `-1 / 8` produces `-0.13`. Scale zero rounds to a whole number.
`scale` is rejected for other operators.

Results are numeric `BigDecimal` values, not formatted strings. Scale controls
rounding rather than fixed-width CSV output or trailing zeroes. Invalid operands,
division by zero (including a blank divisor), missing configured sources, and
non-finite results fail the transformation.
