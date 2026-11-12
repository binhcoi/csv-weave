require "rails_helper"

RSpec.describe FileTypeConfigurationLoader do
  let(:file_type) { FileType.create!(name: "Amounts") }
  let(:amount) { file_type.columns.create!(name: "amount", position: 3) }
  let(:rule) do
    amount.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericRangeValidator"),
                               input_json: { "min" => 0, "max" => 100 })
  end

  it "raises RecordNotFound for a missing file type" do
    expect { described_class.load(0) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  context "with saved configuration" do
    before { Rails.application.load_seed }

    it "loads ordered columns and validators without requiring a map" do
      rule
      name = file_type.columns.create!(name: "name", position: 0)
      name.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "RequiredValidator"), input_json: nil)
      amount.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "RequiredValidator"))

      configuration = described_class.load(file_type.id)

      expect(configuration.file_type.id).to eq(file_type.id)
      expect(configuration.columns.map(&:id)).to eq([name.id, amount.id])
      expect(configuration.validators.map { |processor| [processor.column.id, processor.class] }).to eq([
        [name.id, Validators::RequiredValidator],
        [amount.id, Validators::NumericRangeValidator],
        [amount.id, Validators::RequiredValidator],
      ])
      expect(TransformMap.count).to eq(0)
    end

    it "allows a file type with no validation rules" do
      amount

      configuration = described_class.load(file_type.id)

      expect(configuration.columns.map(&:name)).to eq(["amount"])
      expect(configuration.validators).to be_empty
    end

    it "revalidates saved rule JSON against its current catalog schema" do
      rule.update_columns(input_json: { "min" => "invalid" })

      expect { described_class.load(file_type.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(hash_including(resource: "validation", id: rule.id, field: "input_json", message: /min/))
      end
    end

    it "revalidates same-row references after a peer column is deleted" do
      peer = file_type.columns.create!(name: "peer", position: 4)
      comparison = amount.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericComparisonValidator"),
                                              input_json: { "other_column" => peer.name, "operator" => "<=" })
      peer.destroy!

      expect { described_class.load(file_type.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(hash_including(resource: "validation", id: comparison.id, field: "input_json", message: /peer/))
      end
    end

    it "rejects invalid catalogs before resolving a processor" do
      rule.column_validator.update_columns(processor_class: "Kernel")

      expect(ActiveSupport::Inflector).not_to receive(:constantize)
      expect { described_class.load(file_type.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(hash_including(resource: "column_validator", id: rule.column_validator_id, field: "processor_class"))
      end
    end
  end
end
