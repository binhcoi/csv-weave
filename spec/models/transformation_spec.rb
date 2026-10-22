require "rails_helper"

RSpec.describe Transformation, type: :model do
  subject(:transformation) do
    described_class.new(transform_map: transform_map, output_column: output_column,
                        column_transformer: column_transformer)
  end

  let(:input_file_type) { FileType.create!(name: "Customer import") }
  let(:output_file_type) { FileType.create!(name: "Customer export") }
  let(:transform_map) do
    TransformMap.create!(name: "Customer conversion", input_file_type: input_file_type,
                         output_file_type: output_file_type)
  end
  let(:output_column) { Column.create!(file_type: output_file_type, name: "email", position: 0) }
  let(:column_transformer) { ColumnTransformer.create!(processor_class: "CopyTransformer") }

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

  it "defaults omitted parameters to an empty object and accepts them" do
    transformation.save!

    expect(transformation.reload.input_json).to eq({})
  end

  it "persists and updates nested JSON parameters" do
    transformation.input_json = { "name" => "email", "options" => { "fallback" => nil } }
    transformation.save!

    expect(transformation.reload.input_json).to eq(
      "name" => "email", "options" => { "fallback" => nil },
    )

    transformation.update!(input_json: { "name" => "contact_email" })

    expect(transformation.reload.input_json).to eq("name" => "contact_email")
  end

  it "retrieves transformations through the correct map and output column" do
    transformation.save!
    other_column = Column.create!(file_type: output_file_type, name: "customer_id", position: 1)
    other_transformation = described_class.create!(transform_map: transform_map, output_column: other_column,
                                                 column_transformer: column_transformer)

    expect(transform_map.transformations.reload).to contain_exactly(transformation, other_transformation)
    expect(output_column.transformations.reload).to contain_exactly(transformation)
    expect(other_column.transformations.reload).to contain_exactly(other_transformation)
  end

  it "builds a transformation through its map" do
    rule = transform_map.transformations.create!(output_column: output_column,
                                                column_transformer: column_transformer)

    expect(rule.reload.transform_map).to eq(transform_map)
    expect(rule.output_column).to eq(output_column)
  end

  it "builds a transformation through its output column" do
    rule = output_column.transformations.create!(transform_map: transform_map,
                                                column_transformer: column_transformer)

    expect(rule.reload.transform_map).to eq(transform_map)
    expect(rule.output_column).to eq(output_column)
  end

  context "with an existing transformation" do
    before { transformation.save! }

    it "rejects duplicate output targets within a map through model validation" do
      duplicate = described_class.new(transform_map: transform_map, output_column: output_column,
                                      column_transformer: column_transformer, input_json: { "name" => "other" })

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.of_kind?(:output_column_id, :taken)).to be true
    end

    it "allows updating an existing transformation without conflicting with itself" do
      transformation.update!(input_json: { "name" => "email" })

      expect(transformation.reload.input_json).to eq("name" => "email")
    end

    it "allows the same output column in a different map" do
      other_map = TransformMap.create!(name: "Alternative conversion", input_file_type: input_file_type,
                                       output_file_type: output_file_type)
      other_transformation = described_class.create!(transform_map: other_map, output_column: output_column,
                                                   column_transformer: column_transformer)

      expect(other_transformation.reload.output_column).to eq(output_column)
      expect(other_map.transformations.reload).to contain_exactly(other_transformation)
      expect(transform_map.transformations.reload).to contain_exactly(transformation)
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
    [:transform_map_id, :output_column_id, :column_transformer_id, :input_json].each do |attribute|
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
          described_class.insert_all!([attributes.merge(input_json: { "name" => "other" })])
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
