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
    transformer = FactoryBot.create(:column_transformer, input_schema: { "type" => "object" })
    integer_transformer = FactoryBot.create(:column_transformer, processor_class: "IntegerParseTransformer",
                                           input_schema: { "type" => "object" })
    decimal_transformer = FactoryBot.create(:column_transformer, processor_class: "DecimalParseTransformer",
                                           input_schema: { "type" => "object" })
    numeric_transformers = [integer_transformer, decimal_transformer]

    Rails.application.load_seed
    length_schema = length_validator.reload.input_schema
    regex_schema = regex_validator.reload.input_schema
    length_validator.update!(description: "Outdated description", input_schema: nil)
    regex_validator.update!(description: "Outdated description", input_schema: nil)
    numeric_validator.update!(description: "Outdated description", input_schema: nil)
    numeric_transformers.each { |catalog| catalog.update!(description: "Outdated description", input_schema: nil) }
    Rails.application.load_seed

    expect(ColumnValidator.pluck(:id)).to contain_exactly(validator.id, length_validator.id, regex_validator.id,
                                                       numeric_validator.id)
    expect(ColumnTransformer.pluck(:id)).to contain_exactly(transformer.id, integer_transformer.id, decimal_transformer.id)
    expect(validator.reload.description).to eq("Validate a column has a nonblank value")
    expect(length_validator.reload.description).to eq("Validate a column length is within range")
    expect(regex_validator.reload.description).to eq("Validate a column value against a regular expression")
    expect(numeric_validator.reload.description).to eq("Validate a column value is within an inclusive numeric range")
    expect(transformer.reload.description).to eq("Copy the value of an input column to an output column")
    expect(integer_transformer.reload.description).to eq("Parse an input column as a base-10 integer")
    expect(decimal_transformer.reload.description).to eq("Parse an input column as a finite decimal without losing precision")
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
