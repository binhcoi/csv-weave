require "rails_helper"

RSpec.describe TransformMap, type: :model do
  subject(:mapping) do
    described_class.new(name: "Customer conversion", input_file_type: input_file_type,
                       output_file_type: output_file_type)
  end

  let(:input_file_type) { FileType.create!(name: "Customer import") }
  let(:output_file_type) { FileType.create!(name: "Customer export") }

  it "persists its name and input/output file types" do
    mapping.save!
    mapping.reload

    expect(mapping.name).to eq("Customer conversion")
    expect(mapping.input_file_type).to eq(input_file_type)
    expect(mapping.output_file_type).to eq(output_file_type)
  end

  { "nil" => nil, "empty" => "", "whitespace" => " \t\n" }.each do |description, value|
    it "rejects #{description} names" do
      mapping.name = value

      expect(mapping).not_to be_valid
      expect(mapping.errors.of_kind?(:name, :blank)).to be true
    end
  end

  [:input_file_type, :output_file_type].each do |association|
    it "requires an #{association}" do
      mapping.public_send("#{association}=", nil)

      expect(mapping).not_to be_valid
      expect(mapping.errors.of_kind?(association, :blank)).to be true
    end
  end

  it "allows the same file type as input and output" do
    mapping.output_file_type = input_file_type
    mapping.save!
    mapping.reload

    expect(mapping.input_file_type).to eq(input_file_type)
    expect(mapping.output_file_type).to eq(input_file_type)
  end

  it "allows multiple maps with the same name" do
    mapping.save!
    other_mapping = described_class.create!(name: mapping.name, input_file_type: output_file_type,
                                           output_file_type: input_file_type)

    expect(other_mapping.reload.name).to eq(mapping.name)
    expect(other_mapping.id).not_to eq(mapping.id)
  end

  it "allows multiple maps for the same input/output pair" do
    mapping.save!
    other_mapping = described_class.create!(name: "Alternative conversion", input_file_type: input_file_type,
                                           output_file_type: output_file_type)

    expect(other_mapping.reload.input_file_type).to eq(input_file_type)
    expect(other_mapping.output_file_type).to eq(output_file_type)
    expect(other_mapping.id).not_to eq(mapping.id)
  end

  it "returns maps through the correct input/output reverse associations" do
    mapping.save!
    reverse_mapping = described_class.create!(name: "Reverse conversion", input_file_type: output_file_type,
                                             output_file_type: input_file_type)

    expect(input_file_type.input_maps.reload).to contain_exactly(mapping)
    expect(input_file_type.output_maps.reload).to contain_exactly(reverse_mapping)
    expect(output_file_type.input_maps.reload).to contain_exactly(reverse_mapping)
    expect(output_file_type.output_maps.reload).to contain_exactly(mapping)
  end

  it "builds a map through the input file type" do
    new_mapping = input_file_type.input_maps.build(name: "Customer conversion", output_file_type: output_file_type)
    new_mapping.save!

    expect(new_mapping.reload.input_file_type).to eq(input_file_type)
    expect(new_mapping.output_file_type).to eq(output_file_type)
  end

  it "builds a map through the output file type" do
    new_mapping = output_file_type.output_maps.build(name: "Customer conversion", input_file_type: input_file_type)
    new_mapping.save!

    expect(new_mapping.reload.input_file_type).to eq(input_file_type)
    expect(new_mapping.output_file_type).to eq(output_file_type)
  end

  describe "database constraints" do
    let(:attributes) do
      { name: "Customer conversion", input_file_type_id: input_file_type.id,
        output_file_type_id: output_file_type.id }
    end

    # insert_all! bypasses model validations; savepoints isolate expected SQL failures.
    [:name, :input_file_type_id, :output_file_type_id].each do |attribute|
      it "rejects a NULL #{attribute} without model validation" do
        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([attributes.merge(attribute => nil)])
          end
        end.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    [:input_file_type_id, :output_file_type_id].each do |attribute|
      it "rejects a nonexistent #{attribute} without model validation" do
        invalid_attributes = attributes.merge(attribute => FileType.maximum(:id) + 1)

        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([invalid_attributes])
          end
        end.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end
  end
end
