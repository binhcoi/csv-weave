require "rails_helper"

RSpec.describe "Catalog seeds", type: :model do
  it "updates schemas and descriptions without duplicating existing catalog entries" do
    validator = FactoryBot.create(:column_validator, input_schema: { "type" => "object" })
    transformer = FactoryBot.create(:column_transformer, input_schema: { "type" => "object" })

    2.times { Rails.application.load_seed }

    expect(ColumnValidator.pluck(:id)).to eq([validator.id])
    expect(ColumnTransformer.pluck(:id)).to eq([transformer.id])
    expect(validator.reload.description).to eq("Validate a column has a nonblank value")
    expect(transformer.reload.description).to eq("Copy the value of an input column to an output column")
    expect(validator.input_schema).to be_nil
    expect(transformer.input_schema).to eq(
      "type" => "object",
      "properties" => { "name" => { "type" => "string", "minLength" => 1 } },
      "required" => ["name"],
      "additionalProperties" => false,
    )
  end

  it "validates saved rules against the seeded schemas" do
    Rails.application.load_seed
    file_type = FileType.create!(name: "Customer import")
    column = Column.create!(file_type: file_type, name: "email", position: 0)
    map = TransformMap.create!(name: "Customer conversion", input_file_type: file_type,
                               output_file_type: file_type)
    validation = Validation.create!(column: column, column_validator: ColumnValidator.first!)
    transformation = Transformation.create!(transform_map: map, output_column: column,
                                            column_transformer: ColumnTransformer.first!,
                                            input_json: { "name" => "email" })

    expect(validation.update(input_json: nil)).to be true
    expect(transformation.update(input_json: { "name" => 123 })).to be false
    expect(validation.reload.input_json).to be_nil
    expect(transformation.reload.input_json).to eq("name" => "email")
  end
end
