require "rails_helper"
require "csv"

RSpec.describe ConversionConfigurationLoader do
  let(:input_type) { FileType.create!(name: "Input") }
  let(:output_type) { FileType.create!(name: "Output") }
  let(:source_column) { input_type.columns.create!(name: "amount", position: 2) }
  let(:output_column) { output_type.columns.create!(name: "total", position: 4) }
  let(:mapping) { TransformMap.create!(name: "Conversion", input_file_type: input_type, output_file_type: output_type) }
  let(:transformation) do
    mapping.transformations.create!(output_column: output_column, input_json: { "source_column" => source_column.name },
                                    column_transformer: ColumnTransformer.find_by!(processor_class: "DecimalParseTransformer"))
  end
  let(:input_rule) do
    source_column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "RequiredValidator"), input_json: nil)
  end
  let(:output_rule) do
    output_column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericRangeValidator"),
                                      input_json: { "min" => 0, "max" => 100 })
  end

  it "distinguishes a missing map from an invalid saved configuration" do
    expect { described_class.load(0) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  context "with a saved configuration" do
    before do
      Rails.application.load_seed
      transformation
      input_rule
      output_rule
    end

    it "orders columns by position and validators by column position then rule ID" do
      optional = output_type.columns.create!(name: "optional", position: 0)
      first_input = input_type.columns.create!(name: "first", position: 0)
      later_rule = source_column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "LengthValidator"),
                                                    input_json: { "max" => 20 })
      # Earlier-position columns deliberately receive rules with later IDs.
      first_input.validations.create!(column_validator: input_rule.column_validator, input_json: nil)
      optional.validations.create!(column_validator: later_rule.column_validator, input_json: { "max" => 5 })
      output_column.validations.create!(column_validator: input_rule.column_validator, input_json: nil)

      configuration = described_class.load(mapping.id)

      expect(configuration.map.id).to eq(mapping.id)
      expect(configuration.input_columns.map(&:id)).to eq([first_input.id, source_column.id])
      expect(configuration.output_columns.map(&:id)).to eq([optional.id, output_column.id])
      expect(configuration.input_validators.map { |processor| [processor.column.id, processor.class] }).to eq([
        [first_input.id, Validators::RequiredValidator],
        [source_column.id, Validators::RequiredValidator],
        [source_column.id, Validators::LengthValidator],
      ])
      expect(configuration.input_validators.map(&:input_json)).to eq([nil, nil, later_rule.input_json])
      expect(configuration.transformers.map(&:class)).to eq([Transformers::DecimalParseTransformer])
      expect(configuration.output_validators.map { |processor| [processor.column.id, processor.class] }).to eq([
        [optional.id, Validators::LengthValidator],
        [output_column.id, Validators::NumericRangeValidator],
        [output_column.id, Validators::RequiredValidator],
      ])
    end

    it "processes different row values and validation outcomes without querying the database" do
      peer = input_type.columns.create!(name: "limit", position: 5)
      source_column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericComparisonValidator"),
                                        input_json: { "other_column" => peer.name, "operator" => "<=" })
      configuration = described_class.load(mapping.id)
      queries = []
      callback = ->(_name, _start, _finish, _id, payload) { queries << payload.fetch(:sql) }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        [["20", "12.50", true], ["100", "150.25", false]].each do |limit, amount, accepted|
          source = CSV::Row.new(["limit", "amount"], [limit, amount])
          destination = CSV::Row.new(configuration.output_columns.map(&:name), [nil])

          expect(configuration.input_validators.map { |processor| processor.validate(source) }).to eq([true, accepted])
          expect(configuration.transformers.map { |processor| processor.transform(source, destination) }).to all(be_nil)
          expect(configuration.output_validators.map { |processor| processor.validate(destination) }).to eq([accepted])
          expect(destination["total"]).to eq(BigDecimal(amount))
        end
      end

      expect(queries).to be_empty
    end

    it "supports using the same file type for both sides without duplicating its rules" do
      mapping.transformations.destroy_all
      mapping.update!(output_file_type: input_type)
      mapping.transformations.create!(output_column: source_column, input_json: { "source_column" => source_column.name },
                                      column_transformer: ColumnTransformer.find_by!(processor_class: "CopyTransformer"))

      configuration = described_class.load(mapping.id)

      expect(configuration.input_columns).to eq(configuration.output_columns)
      expect(configuration.input_validators.size).to eq(1)
      expect(configuration.output_validators.size).to eq(1)
    end

    it "allows file types with no rules and a map with no transformations" do
      mapping.transformations.destroy_all
      source_column.validations.destroy_all
      output_column.validations.destroy_all

      configuration = described_class.load(mapping.id)

      expect(configuration.input_validators).to be_empty
      expect(configuration.output_validators).to be_empty
      expect(configuration.transformers).to be_empty
      expect(configuration.output_columns.map(&:name)).to eq(["total"])
    end

    it "keeps a loaded configuration usable after saved configuration changes" do
      configuration = described_class.load(mapping.id)
      output_rule.update!(input_json: { "max" => 1 })
      source_column.update!(name: "renamed_amount")

      source = CSV::Row.new(["amount"], ["12.50"])
      destination = CSV::Row.new(configuration.output_columns.map(&:name), [nil])

      expect(configuration.input_validators.map { |processor| processor.validate(source) }).to all(be true)
      expect(configuration.transformers.map { |processor| processor.transform(source, destination) }).to all(be_nil)
      expect(destination["total"]).to eq(BigDecimal("12.50"))
      expect(configuration.output_validators.map { |processor| processor.validate(destination) }).to all(be true)

      fresh_configuration = described_class.load(mapping.id)
      expect(fresh_configuration.input_columns.map(&:name)).to eq(["renamed_amount"])
      expect(fresh_configuration.output_validators.map { |processor| processor.validate(destination) }).to eq([false])
    end

    it "collects input, transformation, and output configuration errors without changing saved records" do
      input_rule.update_columns(input_json: {})
      required = input_rule.column_validator
      required.update!(input_schema: { "type" => "null" })
      transformation.update_columns(input_json: { "source_column" => "missing" })
      output_rule.update_columns(input_json: { "min" => 10, "max" => 1 })
      records = [mapping, source_column, output_column, input_rule, transformation, output_rule]
      before_attributes = records.map { |record| record.reload.attributes }

      expect { described_class.load(mapping.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(
          { resource: "validation", id: input_rule.id, field: "input_json", message: a_kind_of(String) },
          { resource: "transformation", id: transformation.id, field: "input_json",
            message: 'source column "missing" does not exist in the map\'s input file type' },
          { resource: "validation", id: output_rule.id, field: "input_json", message: "require min <= max" },
        )
      end

      expect(records.map { |record| record.reload.attributes }).to eq(before_attributes)
    end

    it "rejects a source invalidated by changing the map's input file type" do
      replacement = FileType.create!(name: "Different input")
      mapping.update!(input_file_type: replacement)

      expect { described_class.load(mapping.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(hash_including(resource: "transformation", id: transformation.id, field: "input_json"))
      end
    end

    it "revalidates comparison references after a peer column is deleted" do
      peer = input_type.columns.create!(name: "peer", position: 3)
      rule = source_column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericComparisonValidator"),
                                               input_json: { "other_column" => peer.name, "operator" => "<=" })
      peer.destroy!

      expect { described_class.load(mapping.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(hash_including(resource: "validation", id: rule.id, message: /peer.*does not exist/))
      end
    end

    it "rejects output ownership that was changed without model validation" do
      transformation.update_columns(output_column_id: source_column.id)

      expect { described_class.load(mapping.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
        expect(error.errors).to include(resource: "transformation", id: transformation.id, field: "output_column",
                                        message: "must belong to the map's output file type")
      end
    end

    ["column_validator", "column_transformer"].each do |association|
      it "rejects an unallowlisted #{association} before resolving a class" do
        catalog = association == "column_validator" ? input_rule.column_validator : transformation.column_transformer
        catalog.update_columns(processor_class: "Kernel")

        expect(ActiveSupport::Inflector).not_to receive(:constantize)
        expect { described_class.load(mapping.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
          expect(error.errors).to include(hash_including(resource: association, id: catalog.id, field: "processor_class"))
        end
      end

      it "reports a malformed #{association} schema as a configuration error" do
        catalog = association == "column_validator" ? input_rule.column_validator : transformation.column_transformer
        catalog.update_columns(input_schema: { "type" => "invalid" })

        expect { described_class.load(mapping.id) }.to raise_error(described_class::InvalidConfiguration) do |error|
          expect(error.errors).to include(hash_including(resource: association, id: catalog.id, field: "input_schema"))
        end
      end
    end
  end
end
