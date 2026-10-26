require "rails_helper"

RSpec.describe Validation, type: :model do
  subject(:validation) do
    described_class.new(column: column, column_validator: column_validator)
  end

  let(:file_type) { FileType.create!(name: "Customer import") }
  let(:column) { Column.create!(file_type: file_type, name: "email", position: 0) }
  let(:column_validator) { FactoryBot.create(:column_validator) }

  it "persists its column and validator catalog entry" do
    validation.save!
    validation.reload

    expect(validation.column).to eq(column)
    expect(validation.column_validator).to eq(column_validator)
  end

  [:column, :column_validator].each do |association|
    it "requires a #{association}" do
      validation.public_send("#{association}=", nil)

      expect(validation).not_to be_valid
      expect(validation.errors.of_kind?(association, :blank)).to be true
    end

    it "rejects a nonexistent #{association}" do
      model = described_class.reflect_on_association(association).klass
      validation.public_send("#{association}_id=", model.maximum(:id).to_i + 1)

      expect(validation).not_to be_valid
      expect(validation.errors.of_kind?(association, :blank)).to be true
    end
  end

  it "defaults omitted parameters to an empty object and accepts them" do
    validation.save!

    expect(validation.reload.input_json).to eq({})
  end

  it "persists and updates nested JSON parameters" do
    column_validator.update!(input_schema: {
      "type" => "object",
      "properties" => {
        "message" => { "type" => "string" },
        "options" => {
          "type" => "object",
          "properties" => { "trim" => { "type" => "boolean" } },
          "additionalProperties" => false,
        },
      },
      "additionalProperties" => false,
    })
    validation.input_json = { "message" => "Email is required", "options" => { "trim" => true } }
    validation.save!

    expect(validation.reload.input_json).to eq(
      "message" => "Email is required", "options" => { "trim" => true },
    )

    validation.update!(input_json: {})

    expect(validation.reload.input_json).to eq({})
  end

  it "retrieves rules through the correct column and catalog associations" do
    validation.save!
    other_column = Column.create!(file_type: file_type, name: "customer_id", position: 1)
    other_validation = described_class.create!(column: other_column, column_validator: column_validator)

    expect(column.validations.reload).to contain_exactly(validation)
    expect(other_column.validations.reload).to contain_exactly(other_validation)
    expect(column_validator.validations.reload).to contain_exactly(validation, other_validation)
  end

  it "builds a rule through its column" do
    rule = column.validations.create!(column_validator: column_validator)

    expect(rule.reload.column).to eq(column)
    expect(rule.column_validator).to eq(column_validator)
  end

  it "builds a rule through its validator catalog entry" do
    rule = column_validator.validations.create!(column: column)

    expect(rule.reload.column).to eq(column)
    expect(rule.column_validator).to eq(column_validator)
  end

  describe "input schema validation" do
    let(:column_validator) do
      FactoryBot.create(:column_validator, input_schema: {
        "type" => "object", "properties" => {}, "additionalProperties" => false,
      })
    end

    {
      "NULL" => nil,
      "array" => [],
      "string" => "email",
      "number" => 1,
      "boolean" => true,
      "unexpected parameter" => { "unexpected" => true },
    }.each do |description, parameters|
      it "rejects #{description} parameters when the schema requires an empty object" do
        validation.input_json = parameters

        expect(validation).not_to be_valid
        expect(validation.errors[:input_json]).not_to be_empty
      end
    end

    it "rejects invalid updates without changing the saved parameters" do
      validation.save!

      expect(validation.update(input_json: { "unexpected" => true })).to be false
      expect(validation.errors[:input_json].join).to include("unexpected")
      expect(validation.reload.input_json).to eq({})
    end

    it "reports an invalid catalog schema as an error instead of raising" do
      column_validator.input_schema = { "type" => "unknown" }

      expect(validation).not_to be_valid
      expect(validation.errors[:input_json].join).to include("catalog input schema is invalid")
    end
  end

  it "allows NULL parameters when the validator has no schema" do
    validation.input_json = nil
    validation.save!

    expect(validation.reload.input_json).to be_nil
  end

  describe "length configuration" do
    let(:column_validator) do
      Rails.application.load_seed
      ColumnValidator.find_by!(processor_class: "LengthValidator")
    end

    [
      { "min" => 0 },
      { "max" => 0 },
      { "min" => 2, "max" => 5 },
      { "min" => 2, "max" => 2 },
    ].each do |parameters|
      it "persists valid bounds #{parameters.inspect}" do
        validation.input_json = parameters
        validation.save!

        expect(validation.reload.input_json).to eq(parameters)
      end
    end

    it "requires at least one bound when parameters are omitted" do
      expect(validation.save).to be false
      expect(validation.errors[:input_json].join).to include("at least")
    end

    it "rejects reversed bounds without changing a saved rule" do
      validation.input_json = { "min" => 2, "max" => 5 }
      validation.save!

      expect(validation.update(input_json: { "min" => 6, "max" => 5 })).to be false
      expect(validation.errors[:input_json].join).to include("min <= max")
      expect(validation.reload.input_json).to eq("min" => 2, "max" => 5)
    end

    ["min", "max"].each do |bound|
      { "negative" => -1, "string" => "2", "fractional" => 1.5, "NULL" => nil }.each do |description, value|
        it "rejects a #{description} #{bound} through the seeded schema" do
          validation.input_json = { bound => value }

          expect(validation.save).to be false
          expect(validation.errors[:input_json].join).to include("/#{bound}")
        end
      end
    end

    it "rejects NULL parameters before attempting processor configuration checks" do
      validation.input_json = nil

      expect(validation.save).to be false
      expect(validation.errors[:input_json]).not_to be_empty
    end
  end

  describe "database constraints" do
    let(:attributes) do
      { column_id: column.id, column_validator_id: column_validator.id, input_json: {} }
    end

    it "defaults omitted parameters to an empty object without model validation" do
      result = described_class.insert_all!([attributes.except(:input_json)])

      expect(described_class.find(result.rows.first.first).input_json).to eq({})
    end

    # insert_all! bypasses model validations; savepoints isolate expected SQL failures.
    [:column_id, :column_validator_id].each do |attribute|
      it "rejects a NULL #{attribute} without model validation" do
        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([attributes.merge(attribute => nil)])
          end
        end.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    { column_id: Column, column_validator_id: ColumnValidator }.each do |attribute, model|
      it "rejects a nonexistent #{attribute} without model validation" do
        invalid_attributes = attributes.merge(attribute => model.maximum(:id).to_i + 1)

        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([invalid_attributes])
          end
        end.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end
  end
end
