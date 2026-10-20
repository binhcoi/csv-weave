require "rails_helper"

RSpec.describe Column, type: :model do
  subject(:column) do
    described_class.new(file_type: file_type, name: "email", position: 1)
  end

  let(:file_type) { FileType.create!(name: "Customer import") }

  it "persists its name, position, and file type" do
    column.save!
    column.reload

    expect(column.name).to eq("email")
    expect(column.position).to eq(1)
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
    "zero" => 0,
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
      duplicate = described_class.new(file_type: file_type, name: "customer_id", position: 1)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.of_kind?(:position, :taken)).to be true
    end

    it "allows the same name and position in a different file type" do
      other_file_type = FileType.create!(name: "Customer export")
      other_column = described_class.create!(file_type: other_file_type, name: "email", position: 1)

      expect(other_column.reload.file_type).to eq(other_file_type)
    end

    it "allows gaps between positions" do
      later_column = described_class.create!(file_type: file_type, name: "customer_id", position: 3)

      expect(later_column.reload.position).to eq(3)
    end
  end

  describe "database constraints" do
    let(:attributes) { { file_type_id: file_type.id, name: "email", position: 1 } }

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

    [0, -1].each do |position|
      it "rejects position #{position} without model validation" do
        expect do
          described_class.transaction(requires_new: true) do
            described_class.insert_all!([attributes.merge(position: position)])
          end
        end.to raise_error(ActiveRecord::StatementInvalid) { |error|
          expect(error.cause).to be_a(PG::CheckViolation)
        }
      end
    end
  end
end
