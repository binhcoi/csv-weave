require "rails_helper"

RSpec.describe ColumnValidator, type: :model do
  subject(:validator) do
    FactoryBot.build(:column_validator)
  end

  it "persists its processor class and description" do
    validator.save!
    validator.reload

    expect(validator.processor_class).to eq("RequiredValidator")
    expect(validator.description).to eq("Column requires a value")
  end

  it "allows an omitted description" do
    validator = FactoryBot.create(:column_validator, description: nil)

    expect(validator.reload.description).to be_nil
  end

  { "nil" => nil, "empty" => "", "whitespace" => " \t\n" }.each do |description, value|
    it "rejects #{description} processor names" do
      validator.processor_class = value

      expect(validator).not_to be_valid
      expect(validator.errors.of_kind?(:processor_class, :blank)).to be true
    end
  end

  ["UnknownValidator", "BaseValidator", "Kernel"].each do |processor_class|
    it "rejects the unsupported processor #{processor_class}" do
      validator.processor_class = processor_class

      expect(validator).not_to be_valid
      expect(validator.errors.of_kind?(:processor_class, :inclusion)).to be true
    end
  end

  it "rejects duplicate catalog entries for the same processor" do
    validator.save!
    duplicate = FactoryBot.build(:column_validator)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:processor_class, :taken)).to be true
  end

  describe "#get_validator" do
    let(:column) { Column.new(name: "email", position: 0) }
    let(:input_json) { {} }

    it "resolves a saved catalog entry and passes its configuration to the processor" do
      validator.save!
      validator.reload

      expect(Validators::RequiredValidator).to receive(:new).with(column, input_json).and_call_original

      expect(validator.get_validator(column, input_json)).to be_an_instance_of(Validators::RequiredValidator)
    end

    {
      "nil" => nil,
      "empty" => "",
      "whitespace" => " \t\n",
      "unknown" => "UnknownValidator",
      "base class" => "BaseValidator",
      "unrelated class" => "Kernel",
    }.each do |description, value|
      it "rejects an unsaved #{description} identifier before resolving any class" do
        validator.processor_class = value

        expect(ActiveSupport::Inflector).not_to receive(:constantize)
        expect { validator.get_validator(column, input_json) }.to raise_error(ArgumentError, /validator/)
      end
    end
  end

  describe "database constraints" do
    it "rejects a NULL processor class without model validation" do
      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([{ processor_class: nil, input_schema: validator.input_schema }])
        end
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects duplicate processor classes without model validation" do
      validator.save!

      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([{ processor_class: "RequiredValidator", input_schema: validator.input_schema }])
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
