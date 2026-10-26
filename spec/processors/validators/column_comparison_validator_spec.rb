require "rails_helper"
require "csv"

RSpec.describe Validators::ColumnComparisonValidator do
  subject(:processor) { described_class.new(validation) }

  let(:file_type) do
    FileType.new(name: "Input").tap do |type|
      type.columns.build(name: "value", position: 0)
      type.columns.build(name: "other_value", position: 1)
    end
  end
  let(:validation) do
    Validation.new(column: file_type.columns.first,
                   input_json: { "other_column" => "other_value", "operator" => "==" })
  end
  let(:row) { CSV::Row.new(["value", "other_value"], ["same", "same"]) }

  it "rejects a missing configured comparison column before comparing values" do
    validation.input_json["other_column"] = "missing"

    expect(processor.validate(row)).to be false
  end

  it "rejects unsupported operators before invoking any method on the values" do
    validation.input_json["operator"] = "clear"

    expect(processor.validate(row)).to be false
    expect(row.fields).to eq(["same", "same"])
  end
end
