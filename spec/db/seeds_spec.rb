require "rails_helper"

RSpec.describe "Catalog seeds", type: :model do
  it "updates schemas and descriptions without duplicating existing catalog entries" do
    validator = FactoryBot.create(:column_validator, input_schema: { "type" => "object" })
    length_validator = FactoryBot.create(:column_validator, processor_class: "LengthValidator",
                                        input_schema: { "type" => "object" })
    regex_validator = FactoryBot.create(:column_validator, processor_class: "RegexValidator",
                                       input_schema: { "type" => "object" })
    numeric_validator = FactoryBot.create(:column_validator, processor_class: "NumericRangeValidator",
                                         input_schema: { "type" => "object" })
    date_validator = FactoryBot.create(:column_validator, processor_class: "DateValidator",
                                      input_schema: { "type" => "object" })
    string_comparison = FactoryBot.create(:column_validator, processor_class: "StringComparisonValidator",
                                         input_schema: { "type" => "object" })
    numeric_comparison = FactoryBot.create(:column_validator, processor_class: "NumericComparisonValidator",
                                          input_schema: { "type" => "object" })
    comparison_validators = [string_comparison, numeric_comparison]
    transformer = FactoryBot.create(:column_transformer, input_schema: { "type" => "object" })
    integer_transformer = FactoryBot.create(:column_transformer, processor_class: "IntegerParseTransformer",
                                           input_schema: { "type" => "object" })
    decimal_transformer = FactoryBot.create(:column_transformer, processor_class: "DecimalParseTransformer",
                                           input_schema: { "type" => "object" })
    numeric_transformers = [integer_transformer, decimal_transformer]
    concatenate_transformer = FactoryBot.create(:column_transformer, processor_class: "ConcatenateTransformer",
                                               input_schema: { "type" => "object" })
    substring_transformer = FactoryBot.create(:column_transformer, processor_class: "SubstringTransformer",
                                             input_schema: { "type" => "object" })
    truncate_transformer = FactoryBot.create(:column_transformer, processor_class: "TruncateTransformer",
                                            input_schema: { "type" => "object" })
    date_transformer = FactoryBot.create(:column_transformer, processor_class: "DateParseTransformer",
                                        input_schema: { "type" => "object" })
    format_transformer = FactoryBot.create(:column_transformer, processor_class: "FormatStringTransformer",
                                          input_schema: { "type" => "object" })
    arithmetic_transformer = FactoryBot.create(:column_transformer, processor_class: "ArithmeticTransformer",
                                              input_schema: { "type" => "object" })

    Rails.application.load_seed
    length_schema = length_validator.reload.input_schema
    regex_schema = regex_validator.reload.input_schema
    length_validator.update!(description: "Outdated description", input_schema: nil)
    regex_validator.update!(description: "Outdated description", input_schema: nil)
    numeric_validator.update!(description: "Outdated description", input_schema: nil)
    date_validator.update!(description: "Outdated description", input_schema: nil)
    comparison_validators.each { |catalog| catalog.update!(description: "Outdated description", input_schema: nil) }
    numeric_transformers.each { |catalog| catalog.update!(description: "Outdated description", input_schema: nil) }
    concatenate_transformer.update!(description: "Outdated description", input_schema: nil)
    substring_transformer.update!(description: "Outdated description", input_schema: nil)
    truncate_transformer.update!(description: "Outdated description", input_schema: nil)
    date_transformer.update!(description: "Outdated description", input_schema: nil)
    format_transformer.update!(description: "Outdated description", input_schema: nil)
    arithmetic_transformer.update!(description: "Outdated description", input_schema: nil)
    Rails.application.load_seed

    expect(ColumnValidator.pluck(:id)).to contain_exactly(validator.id, length_validator.id, regex_validator.id,
                                                       numeric_validator.id, date_validator.id,
                                                       string_comparison.id, numeric_comparison.id)
    expect(ColumnTransformer.pluck(:id)).to contain_exactly(transformer.id, integer_transformer.id,
                                                         decimal_transformer.id, concatenate_transformer.id,
                                                         substring_transformer.id, truncate_transformer.id,
                                                         date_transformer.id, format_transformer.id,
                                                         arithmetic_transformer.id)
    expect(validator.reload.description).to eq("Validate a column has a nonblank value")
    expect(length_validator.reload.description).to eq("Validate a column length is within range")
    expect(regex_validator.reload.description).to eq("Validate a column value against a regular expression")
    expect(numeric_validator.reload.description).to eq("Validate a column value is within an inclusive numeric range")
    expect(date_validator.reload.description).to eq("Validate a column date format and optional inclusive date range")
    expect(string_comparison.reload.description).to eq("Compare two same-row column values as strings in case-sensitive lexicographic order")
    expect(numeric_comparison.reload.description).to eq("Compare two same-row column values as finite numbers")
    expect(transformer.reload.description).to eq("Copy the value of an input column to an output column")
    expect(integer_transformer.reload.description).to eq("Parse an input column as a base-10 integer")
    expect(decimal_transformer.reload.description).to eq("Parse an input column as a finite decimal without losing precision")
    expect(concatenate_transformer.reload.description)
      .to eq("Join nonblank input column values in the configured order with an optional separator")
    expect(substring_transformer.reload.description)
      .to eq("Extract characters from an input column using a zero-based start and length")
    expect(truncate_transformer.reload.description)
      .to eq("Keep up to the configured number of characters from the start of an input column")
    expect(date_transformer.reload.description)
      .to eq("Parse an input column using a date format and write a formatted date string")
    expect(format_transformer.reload.description)
      .to eq("Substitute input column values into a string template with named placeholders")
    expect(arithmetic_transformer.reload.description)
      .to eq("Calculate with two finite numeric input columns using an arithmetic operator")
    expect(validator.input_schema).to be_nil
    expect(length_validator.input_schema).to eq(length_schema)
    expect(regex_validator.input_schema).to eq(regex_schema)
    expect(numeric_validator.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "min" => { "type" => "number" },
        "max" => { "type" => "number" },
      },
      "additionalProperties" => false,
    )
    expect(date_validator.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "format" => { "type" => "string", "minLength" => 1 },
        "min" => { "type" => "string", "minLength" => 1 },
        "max" => { "type" => "string", "minLength" => 1 },
      },
      "required" => ["format"],
      "additionalProperties" => false,
    )
    expect(string_comparison.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "other_column" => { "type" => "string", "minLength" => 1 },
        "operator" => { "type" => "string", "enum" => ["==", "!=", "<", "<=", ">", ">="] },
      },
      "required" => ["other_column", "operator"],
      "additionalProperties" => false,
    )
    expect(numeric_comparison.input_schema).to eq(string_comparison.input_schema)
    expect(transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_column" => { "type" => "string", "minLength" => 1 },
      },
      "required" => ["source_column"],
      "additionalProperties" => false,
    )
    numeric_transformers.each do |catalog|
      expect(catalog.input_schema).to eq(transformer.input_schema)
    end
    expect(concatenate_transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_columns" => { "type" => "array", "minItems" => 1, "items" => { "type" => "string", "minLength" => 1 } },
        "separator" => { "type" => "string" },
      },
      "required" => ["source_columns"],
      "additionalProperties" => false,
    )
    expect(substring_transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_column" => { "type" => "string", "minLength" => 1 },
        "start" => { "type" => "integer", "minimum" => 0 },
        "length" => { "type" => "integer", "minimum" => 0 },
      },
      "required" => ["source_column", "start", "length"],
      "additionalProperties" => false,
    )
    expect(truncate_transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_column" => { "type" => "string", "minLength" => 1 },
        "length" => { "type" => "integer", "minimum" => 0 },
      },
      "required" => ["source_column", "length"],
      "additionalProperties" => false,
    )
    expect(date_transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_column" => { "type" => "string", "minLength" => 1 },
        "format" => { "type" => "string", "minLength" => 1 },
        "output_format" => { "type" => "string", "minLength" => 1 },
      },
      "required" => ["source_column", "format"],
      "additionalProperties" => false,
    )
    expect(format_transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_columns" => { "type" => "array", "minItems" => 1, "items" => { "type" => "string", "minLength" => 1 } },
        "format" => { "type" => "string" },
      },
      "required" => ["source_columns", "format"],
      "additionalProperties" => false,
    )
    expect(arithmetic_transformer.input_schema).to eq(
      "type" => "object",
      "properties" => {
        "source_columns" => { "type" => "array", "minItems" => 2, "maxItems" => 2, "items" => { "type" => "string", "minLength" => 1 } },
        "operator" => { "type" => "string", "enum" => ["+", "-", "*", "/"] },
        "scale" => { "type" => "integer", "minimum" => 0, "maximum" => 100 },
      },
      "required" => ["source_columns", "operator"],
      "if" => { "properties" => { "operator" => { "const" => "/" } } },
      "then" => { "required" => ["scale"] },
      "else" => { "not" => { "required" => ["scale"] } },
      "additionalProperties" => false,
    )
  end

  it "validates saved rules against the seeded schemas" do
    Rails.application.load_seed
    file_type = FileType.create!(name: "Customer import")
    column = Column.create!(file_type: file_type, name: "email", position: 0)
    map = TransformMap.create!(name: "Customer conversion", input_file_type: file_type,
                               output_file_type: file_type)
    validation = Validation.create!(column: column,
                                    column_validator: ColumnValidator.find_by!(processor_class: "RequiredValidator"))
    transformation = Transformation.create!(transform_map: map, output_column: column,
                                            column_transformer: ColumnTransformer.find_by!(processor_class: "CopyTransformer"),
                                            input_json: { "source_column" => "email" })

    expect(validation.update(input_json: nil)).to be true
    expect(transformation.update(input_json: { "source_column" => 123 })).to be false
    expect(validation.reload.input_json).to be_nil
    expect(transformation.reload.input_json).to eq("source_column" => "email")
  end
end
