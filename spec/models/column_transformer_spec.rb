require "rails_helper"

RSpec.describe ColumnTransformer, type: :model do
  subject(:transformer) do
    described_class.new(processor_class: "CopyTransformer", description: "Copies a source value")
  end

  it "persists its processor class and description" do
    transformer.save!
    transformer.reload

    expect(transformer.processor_class).to eq("CopyTransformer")
    expect(transformer.description).to eq("Copies a source value")
  end

  it "allows an omitted description" do
    transformer = described_class.create!(processor_class: "CopyTransformer")

    expect(transformer.reload.description).to be_nil
  end

  { "nil" => nil, "empty" => "", "whitespace" => " \t\n" }.each do |description, value|
    it "rejects #{description} processor names" do
      transformer.processor_class = value

      expect(transformer).not_to be_valid
      expect(transformer.errors.of_kind?(:processor_class, :blank)).to be true
    end
  end

  ["UnknownTransformer", "BaseTransformer", "Kernel"].each do |processor_class|
    it "rejects the unsupported processor #{processor_class}" do
      transformer.processor_class = processor_class

      expect(transformer).not_to be_valid
      expect(transformer.errors.of_kind?(:processor_class, :inclusion)).to be true
    end
  end

  it "rejects duplicate catalog entries for the same processor" do
    transformer.save!
    duplicate = described_class.new(processor_class: "CopyTransformer")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:processor_class, :taken)).to be true
  end

  describe "#get_transformer" do
    let(:column) { Column.new(name: "email", position: 0) }
    let(:input_json) { { "name" => "source_email" } }

    it "resolves a saved catalog entry and passes its configuration to the processor" do
      transformer.save!
      transformer.reload

      expect(Transformers::CopyTransformer).to receive(:new).with(column, input_json).and_call_original

      expect(transformer.get_transformer(column, input_json)).to be_an_instance_of(Transformers::CopyTransformer)
    end

    {
      "nil" => nil,
      "empty" => "",
      "whitespace" => " \t\n",
      "unknown" => "UnknownTransformer",
      "base class" => "BaseTransformer",
      "unrelated class" => "Kernel"
    }.each do |description, value|
      it "rejects an unsaved #{description} identifier before resolving any class" do
        transformer.processor_class = value

        expect(ActiveSupport::Inflector).not_to receive(:constantize)
        expect { transformer.get_transformer(column, input_json) }.to raise_error(ArgumentError, /transformer/)
      end
    end
  end

  describe "database constraints" do
    it "rejects a NULL processor class without model validation" do
      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([{ processor_class: nil }])
        end
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects duplicate processor classes without model validation" do
      transformer.save!

      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([{ processor_class: "CopyTransformer" }])
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
