require "rails_helper"

RSpec.describe FileType, type: :model do
  subject(:file_type) do
    described_class.new(name: "Customer import", description: "Synthetic customer CSV schema")
  end

  it "is valid with a name" do
    expect(file_type).to be_valid
  end

  { "nil" => nil, "empty" => "", "whitespace" => " \t\n" }.each do |description, value|
    it "rejects #{description} names" do
      file_type = described_class.new(name: value)

      expect(file_type).not_to be_valid
      expect(file_type.errors.of_kind?(:name, :blank)).to be true
    end
  end

  it "is valid without a description" do
    file_type = described_class.create!(name: "Customer import")

    expect(file_type.reload.description).to be_nil
  end

  it "persists its name and description" do
    file_type.save!
    file_type.reload

    expect(file_type.name).to eq("Customer import")
    expect(file_type.description).to eq("Synthetic customer CSV schema")
  end

  it "returns its columns in position order" do
    file_type.save!
    later_column = file_type.columns.create!(name: "email", position: 3)
    first_column = file_type.columns.create!(name: "customer_id", position: 1)

    expect(file_type.columns.reload.to_a).to eq([first_column, later_column])
  end

  it "rejects a NULL name at the database level" do
    file_type.name = nil

    expect do
      described_class.transaction(requires_new: true) do
        file_type.save!(validate: false)
      end
    end.to raise_error(ActiveRecord::NotNullViolation)
  end
end
