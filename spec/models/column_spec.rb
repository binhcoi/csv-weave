require "rails_helper"

RSpec.describe Column, type: :model do
  subject(:column) do
    described_class.new(file_type: file_type, name: "email", position: 0)
  end

  let(:file_type) { FileType.create!(name: "Customer import") }

  it "persists its name, position, and file type" do
    column.save!
    column.reload

    expect(column.name).to eq("email")
    expect(column.position).to eq(0)
    expect(column.file_type).to eq(file_type)
  end

  { "nil" => nil, "empty" => "", "whitespace" => " \t\n" }.each do |description, value|
    it "rejects #{description} names" do
      column.name = value

      expect(column).not_to be_valid
      expect(column.errors.of_kind?(:name, :blank)).to be true
    end
  end

  it "requires a file type" do
    column.file_type = nil

    expect(column).not_to be_valid
    expect(column.errors.of_kind?(:file_type, :blank)).to be true
  end

  {
    "nil" => nil,
    "empty" => "",
    "negative" => -1,
    "fractional" => 1.5,
    "fractional string" => "1.5",
    "nonnumeric" => "first"
  }.each do |description, value|
    it "rejects #{description} positions" do
      column.position = value

      expect(column).not_to be_valid
      expect(column.errors[:position]).not_to be_empty
    end
  end

  context "with an existing column" do
    before { column.save! }

    it "rejects duplicate names within the same file type" do
      duplicate = described_class.new(file_type: file_type, name: "email", position: 2)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.of_kind?(:name, :taken)).to be true
    end

    it "rejects duplicate positions within the same file type" do
      duplicate = described_class.new(file_type: file_type, name: "customer_id", position: 0)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.of_kind?(:position, :taken)).to be true
    end

    it "allows the same name and position in a different file type" do
      other_file_type = FileType.create!(name: "Customer export")
      other_column = described_class.create!(file_type: other_file_type, name: "email", position: 0)

      expect(other_column.reload.file_type).to eq(other_file_type)
    end

    it "allows gaps between positions" do
      later_column = described_class.create!(file_type: file_type, name: "customer_id", position: 3)

      expect(later_column.reload.position).to eq(3)
    end
  end

  describe "deletion" do
    let(:output_type) { FileType.create!(name: "Customer export") }
    let(:output_column) { output_type.columns.create!(name: "contact_email", position: 0) }
    let(:mapping) { TransformMap.create!(name: "Copy email", input_file_type: file_type, output_file_type: output_type) }
    let(:transformation) do
      mapping.transformations.create!(output_column: output_column,
                                      column_transformer: FactoryBot.create(:column_transformer),
                                      input_json: { name: column.name })
    end

    before { column.save! }

    it "rejects deleting a source column and retains its validations" do
      transformation
      rule = column.validations.create!(column_validator: FactoryBot.create(:column_validator))

      expect(column.destroy).to be false
      expect(column.errors[:base]).to include("cannot delete a column used by a transformation")
      expect(described_class.exists?(column.id)).to be true
      expect(Validation.exists?(rule.id)).to be true
      expect(Transformation.exists?(transformation.id)).to be true
    end

    it "rejects deleting an output column" do
      transformation

      expect(output_column.destroy).to be false
      expect(output_column.errors[:base]).to include("cannot delete a column used by a transformation")
      expect(described_class.exists?(output_column.id)).to be true
    end

    it "allows deleting an unused column in a map's input file type" do
      transformation
      unused_column = file_type.columns.create!(name: "phone", position: 1)

      expect(unused_column.destroy).to eq(unused_column)
      expect(described_class.exists?(unused_column.id)).to be false
      expect(Transformation.exists?(transformation.id)).to be true
    end

    it "ignores matching source names in a different file type" do
      transformation
      other_type = FileType.create!(name: "Unrelated import")
      unrelated_column = other_type.columns.create!(name: column.name, position: 0)

      expect(unrelated_column.destroy).to eq(unrelated_column)
      expect(described_class.exists?(unrelated_column.id)).to be false
      expect(Transformation.exists?(transformation.id)).to be true
    end
  end

  describe "database constraints" do
    let(:attributes) { { file_type_id: file_type.id, name: "email", position: 0 } }

    it "allows position zero without model validation" do
      described_class.insert_all!([attributes.merge(position: 0)])

      expect(described_class.find_by!(file_type: file_type, name: "email").position).to eq(0)
    end

    # insert_all! bypasses model validations; savepoints isolate expected SQL failures.
    [:file_type_id, :name, :position].each do |attribute|
      it "rejects a NULL #{attribute} without model validation" do
        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([attributes.merge(attribute => nil)])
          end
        end.to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    it "rejects a reference to a nonexistent file type" do
      invalid_attributes = attributes.merge(file_type_id: FileType.maximum(:id) + 1)

      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([invalid_attributes])
        end
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    { "name" => { position: 2 }, "position" => { name: "customer_id" } }.each do |attribute, overrides|
      it "rejects a duplicate #{attribute} within one file type without model validation" do
        column.save!

        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([attributes.merge(overrides)])
          end
        end.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    it "rejects negative positions without model validation" do
      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([attributes.merge(position: -1)])
        end
      end.to raise_error(ActiveRecord::StatementInvalid) { |error|
        expect(error.cause).to be_a(PG::CheckViolation)
      }
    end
  end
end
