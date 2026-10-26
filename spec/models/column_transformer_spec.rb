require "rails_helper"

RSpec.describe ColumnTransformer, type: :model do
  subject(:transformer) do
    FactoryBot.build(:column_transformer)
  end

  it "persists its processor class and description" do
    transformer.save!
    transformer.reload

    expect(transformer.processor_class).to eq("CopyTransformer")
    expect(transformer.description).to eq("Copies a source value")
  end

  it "allows an omitted description" do
    transformer = FactoryBot.create(:column_transformer, description: nil)

    expect(transformer.reload.description).to be_nil
  end

  { "nil" => nil, "empty" => "", "whitespace" => " \t\n" }.each do |description, value|
    it "rejects #{description} processor names" do
      transformer.processor_class = value

      expect(transformer).not_to be_valid
      expect(transformer.errors.of_kind?(:processor_class, :blank)).to be true
    end
  end

  ["UnknownTransformer", "BaseTransformer", "SingleSourceTransformer", "Kernel"].each do |processor_class|
    it "rejects the unsupported processor #{processor_class}" do
      transformer.processor_class = processor_class

      expect(transformer).not_to be_valid
      expect(transformer.errors.of_kind?(:processor_class, :inclusion)).to be true
    end
  end

  it "rejects duplicate catalog entries for the same processor" do
    transformer.save!
    duplicate = FactoryBot.build(:column_transformer)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:processor_class, :taken)).to be true
  end

  describe "#get_transformer" do
    let(:transformation) { Transformation.new(input_json: { "source_column" => "source_email" }) }

    [Transformers::CopyTransformer, Transformers::IntegerParseTransformer,
     Transformers::DecimalParseTransformer, Transformers::ConcatenateTransformer].each do |processor_class|
      it "resolves #{processor_class.name} and passes the transformation to the processor" do
        transformer.processor_class = processor_class.name.demodulize
        transformer.save!
        transformer.reload

        expect(processor_class).to receive(:new).with(transformation).and_call_original

        expect(transformer.get_transformer(transformation)).to be_an_instance_of(processor_class)
      end
    end

    {
      "nil" => nil,
      "empty" => "",
      "whitespace" => " \t\n",
      "unknown" => "UnknownTransformer",
      "base class" => "BaseTransformer",
      "single-source base class" => "SingleSourceTransformer",
      "unrelated class" => "Kernel"
    }.each do |description, value|
      it "rejects an unsaved #{description} identifier before resolving any class" do
        transformer.processor_class = value
        transformation

        expect(ActiveSupport::Inflector).not_to receive(:constantize)
        expect { transformer.get_transformer(transformation) }.to raise_error(ArgumentError, /transformer/)
      end
    end
  end

  describe "database constraints" do
    it "rejects a NULL processor class without model validation" do
      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([{ processor_class: nil, input_schema: transformer.input_schema }])
        end
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects duplicate processor classes without model validation" do
      transformer.save!

      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([{ processor_class: "CopyTransformer", input_schema: transformer.input_schema }])
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
