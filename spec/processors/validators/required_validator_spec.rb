require "rails_helper"
require "csv"

RSpec.describe Validators::RequiredValidator do
  subject(:processor) { described_class.new(validation) }

  let(:column) { Column.new(name: "contact_email", position: 0) }
  let(:validation) { Validation.new(column: column, input_json: nil) }

  # The configured column is deliberately not the first field in the CSV row.
  let(:row) { CSV::Row.new(["other", "contact_email"], ["unrelated", value]) }

  {
    "a populated field" => "user@example.com",
    "a zero string" => "0",
    "a false string" => "false",
  }.each do |description, field|
    context "with #{description}" do
      let(:value) { field }

      it "accepts the row" do
        expect(processor.validate(row)).to be true
      end
    end
  end

  {
    "a NULL field" => nil,
    "an empty field" => "",
    "a whitespace-only field" => " \t\n",
  }.each do |description, field|
    context "with #{description}" do
      let(:value) { field }

      it "rejects the row despite another field being populated" do
        expect(processor.validate(row)).to be false
      end
    end
  end

  it "rejects a row without the configured header" do
    row = CSV::Row.new(["other"], ["unrelated"])

    expect(processor.validate(row)).to be false
  end
end
