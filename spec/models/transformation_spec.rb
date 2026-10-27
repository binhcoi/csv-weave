require "rails_helper"

RSpec.describe Transformation, type: :model do
  subject(:transformation) do
    described_class.new(transform_map: transform_map, output_column: output_column,
                        column_transformer: column_transformer, input_json: { "source_column" => "email" })
  end

  let(:input_file_type) { FileType.create!(name: "Customer import") }
  let(:output_file_type) { FileType.create!(name: "Customer export") }
  let(:transform_map) do
    TransformMap.create!(name: "Customer conversion", input_file_type: input_file_type,
                         output_file_type: output_file_type)
  end
  let(:output_column) { Column.create!(file_type: output_file_type, name: "email", position: 0) }
  let(:column_transformer) { FactoryBot.create(:column_transformer) }

  before do
    ["email", "contact_email", "customer_id"].each_with_index do |name, position|
      input_file_type.columns.create!(name: name, position: position)
    end
  end

  it "persists its map, output column, and transformer catalog entry" do
    transformation.save!
    transformation.reload

    expect(transformation.transform_map).to eq(transform_map)
    expect(transformation.output_column).to eq(output_column)
    expect(transformation.column_transformer).to eq(column_transformer)
  end

  [:transform_map, :output_column, :column_transformer].each do |association|
    it "requires a #{association}" do
      transformation.public_send("#{association}=", nil)

      expect(transformation).not_to be_valid
      expect(transformation.errors.of_kind?(association, :blank)).to be true
    end

    it "rejects a nonexistent #{association}" do
      model = described_class.reflect_on_association(association).klass
      transformation.public_send("#{association}_id=", model.maximum(:id).to_i + 1)

      expect(transformation).not_to be_valid
      expect(transformation.errors.of_kind?(association, :blank)).to be true
    end
  end

  it "rejects omitted parameters when the transformer requires a source column" do
    rule = described_class.new(transform_map: transform_map, output_column: output_column,
                               column_transformer: column_transformer)

    expect(rule.input_json).to eq({})
    expect(rule).not_to be_valid
    expect(rule.errors[:input_json].join).to include("source_column")
  end

  it "persists and updates source-column parameters" do
    transformation.save!

    expect(transformation.reload.input_json).to eq("source_column" => "email")

    transformation.update!(input_json: { "source_column" => "contact_email" })

    expect(transformation.reload.input_json).to eq("source_column" => "contact_email")
  end

  it "retrieves transformations through the correct map and output column" do
    transformation.save!
    other_column = Column.create!(file_type: output_file_type, name: "customer_id", position: 1)
    other_transformation = described_class.create!(transform_map: transform_map, output_column: other_column,
                                                 column_transformer: column_transformer,
                                                 input_json: { "source_column" => "customer_id" })

    expect(transform_map.transformations.reload).to contain_exactly(transformation, other_transformation)
    expect(output_column.transformations.reload).to contain_exactly(transformation)
    expect(other_column.transformations.reload).to contain_exactly(other_transformation)
  end

  it "builds a transformation through its map" do
    rule = transform_map.transformations.create!(output_column: output_column,
                                                column_transformer: column_transformer,
                                                input_json: { "source_column" => "email" })

    expect(rule.reload.transform_map).to eq(transform_map)
    expect(rule.output_column).to eq(output_column)
  end

  it "builds a transformation through its output column" do
    rule = output_column.transformations.create!(transform_map: transform_map,
                                                column_transformer: column_transformer,
                                                input_json: { "source_column" => "email" })

    expect(rule.reload.transform_map).to eq(transform_map)
    expect(rule.output_column).to eq(output_column)
  end

  context "with an existing transformation" do
    before { transformation.save! }

    it "rejects duplicate output targets within a map through model validation" do
      duplicate = described_class.new(transform_map: transform_map, output_column: output_column,
                                      column_transformer: column_transformer, input_json: { "source_column" => "other" })

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.of_kind?(:output_column_id, :taken)).to be true
    end

    it "allows the same output column in a different map" do
      other_map = TransformMap.create!(name: "Alternative conversion", input_file_type: input_file_type,
                                       output_file_type: output_file_type)
      other_transformation = described_class.create!(transform_map: other_map, output_column: output_column,
                                                   column_transformer: column_transformer,
                                                   input_json: { "source_column" => "email" })

      expect(other_transformation.reload.output_column).to eq(output_column)
      expect(other_map.transformations.reload).to contain_exactly(other_transformation)
      expect(transform_map.transformations.reload).to contain_exactly(transformation)
    end
  end

  describe "input schema validation" do
    {
      "NULL" => nil,
      "array" => [],
      "string" => "email",
      "number" => 1,
      "boolean" => true,
      "NULL source column" => { "source_column" => nil },
      "empty source column" => { "source_column" => "" },
      "unexpected parameter" => { "source_column" => "email", "unexpected" => true },
    }.each do |description, parameters|
      it "rejects #{description} parameters for CopyTransformer" do
        transformation.input_json = parameters

        expect(transformation).not_to be_valid
        expect(transformation.errors[:input_json]).not_to be_empty
      end
    end

    it "rejects a numeric source column and identifies the invalid field" do
      transformation.input_json = { "source_column" => 123 }

      expect(transformation).not_to be_valid
      expect(transformation.errors[:input_json].join).to include("/source_column", "string")
    end

    it "rejects invalid updates without changing the saved parameters" do
      transformation.save!

      expect(transformation.update(input_json: {})).to be false
      expect(transformation.errors[:input_json].join).to include("source_column")
      expect(transformation.reload.input_json).to eq("source_column" => "email")
    end

    it "uses constraints from the selected catalog schema" do
      schema = column_transformer.input_schema.deep_dup
      schema["properties"]["source_column"]["minLength"] = 10
      column_transformer.update!(input_schema: schema)

      expect(transformation).not_to be_valid
      expect(transformation.errors[:input_json].join).to include("/source_column")

      transformation.input_json = { "source_column" => "contact_email" }

      expect(transformation).to be_valid
    end

    it "reports an invalid catalog schema as an error instead of raising" do
      column_transformer.input_schema = { "type" => "unknown" }

      expect(transformation).not_to be_valid
      expect(transformation.errors[:input_json].join).to include("catalog input schema is invalid")
    end
  end

  it "still requires a copy source when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("source column")
  end

  it "rejects an omitted copy source when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    rule = described_class.new(transform_map: transform_map, output_column: output_column,
                               column_transformer: column_transformer)

    expect(rule.save).to be false
    expect(rule.errors[:input_json].join).to include("source column")
  end

  it "rechecks the source against a changed map before saving an update" do
    transformation.save!
    other_input = FileType.create!(name: "Other input")
    other_map = TransformMap.create!(name: "Other map", input_file_type: other_input,
                                    output_file_type: output_file_type)

    expect(transformation.update(transform_map: other_map)).to be false
    expect(transformation.errors[:input_json].join).to include('source column "email"')
    expect(transformation.reload.transform_map).to eq(transform_map)
  end

  ["IntegerParseTransformer", "DecimalParseTransformer"].each do |processor_class|
    context "with the seeded #{processor_class}" do
      let(:column_transformer) do
        Rails.application.load_seed
        ColumnTransformer.find_by!(processor_class: processor_class)
      end

      it "persists a configuration using the shared source setting" do
        transformation.save!

        expect(transformation.reload.input_json).to eq("source_column" => "email")
        expect(transformation.column_transformer).to eq(column_transformer)
      end

      it "rejects a non-string source through its seeded schema without changing the saved rule" do
        transformation.save!

        expect(transformation.update(input_json: { "source_column" => 123 })).to be false
        expect(transformation.errors[:input_json].join).to include("/source_column", "string")
        expect(transformation.reload.input_json).to eq("source_column" => "email")
      end
    end
  end

  context "with the seeded SubstringTransformer" do
    let(:column_transformer) do
      Rails.application.load_seed
      ColumnTransformer.find_by!(processor_class: "SubstringTransformer")
    end
    let(:parameters) { { "source_column" => "email", "start" => 0, "length" => 4 } }

    before { transformation.input_json = parameters }

    it "persists its source, start, and length and protects the source from deletion" do
      transformation.save!

      expect(transformation.reload.input_json).to eq(parameters)
      processor = column_transformer.get_transformer(transformation)
      expect(processor.source_column_names).to eq(["email"])
      source_column = input_file_type.columns.find_by!(name: "email")
      expect(source_column.destroy).to be false
      expect(source_column.errors[:base]).to include("cannot delete a column used by a transformation")
    end

    it "allows zero length and arbitrarily large nonnegative bounds" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("length" => 0))).to be true
      expect(transformation.update(input_json: parameters.merge("start" => 10**100, "length" => 10**100))).to be true
    end

    ["start", "length"].each do |setting|
      it "rejects omitted #{setting}" do
        transformation.input_json = parameters.except(setting)

        expect(transformation.save).to be false
        expect(transformation.errors[:input_json].join).to include(setting)
      end

      { "negative" => -1, "fractional" => 1.5, "string" => "1", "NULL" => nil, "boolean" => true }.each do |description, value|
        it "rejects #{description} #{setting} without changing the saved parameters" do
          transformation.save!

          expect(transformation.update(input_json: parameters.merge(setting => value))).to be false
          expect(transformation.errors[:input_json].join).to include("/#{setting}")
          expect(transformation.reload.input_json).to eq(parameters)
        end
      end

      it "still rejects invalid #{setting} when the catalog has no schema" do
        column_transformer.update!(input_schema: nil)
        transformation.input_json = parameters.merge(setting => -1)

        expect(transformation.save).to be false
        expect(transformation.errors[:input_json]).to include("#{setting} must be a nonnegative integer")
      end
    end

    it "rejects additional settings" do
      transformation.input_json = parameters.merge("unexpected" => true)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include("unexpected")
    end

    it "rejects a source outside the map's input file type" do
      other_type = FileType.create!(name: "Other input")
      other_type.columns.create!(name: "foreign_email", position: 0)
      transformation.input_json = parameters.merge("source_column" => "foreign_email")

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include('source column "foreign_email"')
    end

    it "reports invalid configuration without raising when the schema and parameters are NULL" do
      column_transformer.update!(input_schema: nil)
      transformation.input_json = nil

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include("source column", "start", "length")
    end
  end

  context "with the seeded TruncateTransformer" do
    let(:column_transformer) do
      Rails.application.load_seed
      ColumnTransformer.find_by!(processor_class: "TruncateTransformer")
    end
    let(:parameters) { { "source_column" => "email", "length" => 4 } }

    before { transformation.input_json = parameters }

    it "persists its settings and protects the source from deletion" do
      transformation.save!

      expect(transformation.reload.input_json).to eq(parameters)
      expect(column_transformer.get_transformer(transformation).source_column_names).to eq(["email"])
      source_column = input_file_type.columns.find_by!(name: "email")
      expect(source_column.destroy).to be false
      expect(source_column.errors[:base]).to include("cannot delete a column used by a transformation")
    end

    it "accepts zero and arbitrarily large lengths" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("length" => 0))).to be true
      expect(transformation.update(input_json: parameters.merge("length" => 10**100))).to be true
    end

    it "requires a length" do
      transformation.input_json = parameters.except("length")

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include("length")
    end

    { "negative" => -1, "fractional" => 1.5, "string" => "1", "NULL" => nil, "boolean" => true }.each do |description, value|
      it "rejects #{description} length without changing the saved parameters" do
        transformation.save!

        expect(transformation.update(input_json: parameters.merge("length" => value))).to be false
        expect(transformation.errors[:input_json].join).to include("/length")
        expect(transformation.reload.input_json).to eq(parameters)
      end
    end

    it "still rejects invalid length when the catalog has no schema" do
      column_transformer.update!(input_schema: nil)
      transformation.input_json = parameters.merge("length" => -1)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json]).to include("length must be a nonnegative integer")
    end

    it "rejects additional settings" do
      transformation.input_json = parameters.merge("unexpected" => true)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include("unexpected")
    end

    it "rejects a source outside the map's input file type" do
      other_type = FileType.create!(name: "Other input")
      other_type.columns.create!(name: "foreign_email", position: 0)
      transformation.input_json = parameters.merge("source_column" => "foreign_email")

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include('source column "foreign_email"')
    end

    it "reports invalid configuration without raising when the schema and parameters are NULL" do
      column_transformer.update!(input_schema: nil)
      transformation.input_json = nil

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include("source column", "length")
    end
  end

  context "with the seeded ConcatenateTransformer" do
    let(:column_transformer) do
      Rails.application.load_seed
      ColumnTransformer.find_by!(processor_class: "ConcatenateTransformer")
    end

    it "persists ordered sources, including repetitions, and an optional separator" do
      parameters = { "source_columns" => ["contact_email", "email", "contact_email"] }
      transformation.input_json = parameters
      transformation.save!

      expect(transformation.reload.input_json).to eq(parameters)
      expect(transformation.update(input_json: parameters.merge("separator" => ""))).to be true
      expect(transformation.reload.input_json).to eq(parameters.merge("separator" => ""))
    end

    {
      "omitted sources" => {},
      "empty sources" => { "source_columns" => [] },
      "NULL sources" => { "source_columns" => nil },
      "scalar sources" => { "source_columns" => "email" },
      "empty source name" => { "source_columns" => [""] },
      "non-string source name" => { "source_columns" => [123] },
      "NULL separator" => { "source_columns" => ["email"], "separator" => nil },
      "numeric separator" => { "source_columns" => ["email"], "separator" => 123 },
      "additional setting" => { "source_columns" => ["email"], "unexpected" => true },
    }.each do |description, parameters|
      it "rejects #{description} through the seeded schema" do
        transformation.input_json = parameters

        expect(transformation.save).to be false
        expect(transformation.errors[:input_json]).not_to be_empty
      end
    end

    it "rejects a source in another input type without changing the saved parameters" do
      parameters = { "source_columns" => ["email", "contact_email"], "separator" => ", " }
      transformation.input_json = parameters
      transformation.save!
      other_type = FileType.create!(name: "Other input")
      other_type.columns.create!(name: "foreign_email", position: 0)

      expect(transformation.update(input_json: parameters.merge("source_columns" => ["email", "foreign_email"]))).to be false
      expect(transformation.errors[:input_json].join).to include('source column "foreign_email"')
      expect(transformation.reload.input_json).to eq(parameters)
    end

    it "reports every missing source once" do
      transformation.input_json = { "source_columns" => ["missing_a", "missing_b", "missing_a"] }

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].size).to eq(2)
      expect(transformation.errors[:input_json].join).to include('source column "missing_a"', 'source column "missing_b"')
    end

    it "still requires at least one source when the catalog has no schema" do
      column_transformer.update!(input_schema: nil)
      transformation.input_json = {}

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include("at least one source column")
    end
  end

  describe "database constraints" do
    let(:attributes) do
      { transform_map_id: transform_map.id, output_column_id: output_column.id,
        column_transformer_id: column_transformer.id, input_json: {} }
    end

    it "defaults omitted parameters to an empty object without model validation" do
      result = described_class.insert_all!([attributes.except(:input_json)])

      expect(described_class.find(result.rows.first.first).input_json).to eq({})
    end

    # insert_all! bypasses model validations; savepoints isolate expected SQL failures.
    [:transform_map_id, :output_column_id, :column_transformer_id].each do |attribute|
      it "rejects a NULL #{attribute} without model validation" do
        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([attributes.merge(attribute => nil)])
          end
        end.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    { transform_map_id: TransformMap, output_column_id: Column,
      column_transformer_id: ColumnTransformer }.each do |attribute, model|
      it "rejects a nonexistent #{attribute} without model validation" do
        invalid_attributes = attributes.merge(attribute => model.maximum(:id).to_i + 1)

        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([invalid_attributes])
          end
        end.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end

    it "rejects duplicate output targets within a map without model validation" do
      transformation.save!

      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([attributes.merge(input_json: { "source_column" => "other" })])
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
