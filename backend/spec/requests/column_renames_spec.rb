require "rails_helper"
require "csv"

RSpec.describe "Column renames", type: :request do
  let(:input_type) { FileType.create!(name: "Source") }
  let(:output_type) { FileType.create!(name: "Destination") }
  let(:source_column) { input_type.columns.create!(name: "value", position: 0) }
  let(:output_column) { output_type.columns.create!(name: "result", position: 0) }
  let(:mapping) { TransformMap.create!(name: "Conversion", input_file_type: input_type, output_file_type: output_type) }

  before do
    Rails.application.load_seed
    source_column
  end

  {
    "CopyTransformer" => [{}, "Alex", "Alex"],
    "IntegerParseTransformer" => [{}, "12", 12],
    "DecimalParseTransformer" => [{}, "12.50", BigDecimal("12.50")],
    "SubstringTransformer" => [{ "start" => 1, "length" => 2 }, "abcd", "bc"],
    "TruncateTransformer" => [{ "length" => 2 }, "abcd", "ab"],
    "DateParseTransformer" => [{ "format" => "%d %b %Y", "output_format" => "%m/%d/%Y" }, "12 Apr 2026", "04/12/2026"],
  }.each do |processor, (settings, value, expected)|
    it "updates #{processor} sources and preserves its other settings" do
      rule = add_rule(processor, settings.merge("source_column" => "value"))

      patch "/columns/#{source_column.id}", params: { column: { name: "renamed value 名前" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(rule.reload.input_json).to eq(settings.merge("source_column" => "renamed value 名前"))
      expect(rule).to be_valid
      expect(transformed_value(rule, "renamed value 名前" => value)).to eq(expected)
    end
  end

  it "renames every repeated concatenate source without changing the separator" do
    input_type.columns.create!(name: "other", position: 1)
    rule = add_rule("ConcatenateTransformer", { "source_columns" => ["value", "other", "value"], "separator" => "value" })

    patch "/columns/#{source_column.id}", params: { column: { name: "renamed" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(rule.reload.input_json).to eq("source_columns" => ["renamed", "other", "renamed"], "separator" => "value")
    expect(transformed_value(rule, "renamed" => "A", "other" => "B")).to eq("AvalueBvalueA")
  end

  it "renames both arithmetic operands while preserving division settings" do
    rule = add_rule("ArithmeticTransformer", { "source_columns" => ["value", "value"], "operator" => "/", "scale" => 2 })

    patch "/columns/#{source_column.id}", params: { column: { name: "renamed" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(rule.reload.input_json).to eq("source_columns" => ["renamed", "renamed"], "operator" => "/", "scale" => 2)
    expect(transformed_value(rule, "renamed" => "3")).to eq(BigDecimal("1"))
  end

  it "updates all maps for the source type, including template placeholders, and preserves other types" do
    copy = add_rule("CopyTransformer", { "source_column" => "value" })
    second_map = TransformMap.create!(name: "Formatted", input_file_type: input_type, output_file_type: output_type)
    template = "%{value}/%{value}/%%{value}/%%%{value}/value"
    formatted = add_rule("FormatStringTransformer", { "source_columns" => ["value", "value"], "format" => template }, map: second_map)
    other_type = FileType.create!(name: "Unrelated")
    other_type.columns.create!(name: "value", position: 0)
    other_map = TransformMap.create!(name: "Unrelated", input_file_type: other_type, output_file_type: output_type)
    unrelated = add_rule("CopyTransformer", { "source_column" => "value" }, map: other_map)
    input_type.columns.create!(name: "value_suffix", position: 1)
    other_output = output_type.columns.create!(name: "other", position: 1)
    unreferenced = add_rule("CopyTransformer", { "source_column" => "value_suffix" }, target: other_output)

    patch "/columns/#{source_column.id}", params: { column: { name: "名前 % value" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(copy.reload.input_json).to eq("source_column" => "名前 % value")
    expect(formatted.reload.input_json).to eq(
      "source_columns" => ["名前 % value", "名前 % value"],
      "format" => "%{名前 % value}/%{名前 % value}/%%{value}/%%%{名前 % value}/value",
    )
    expect(transformed_value(formatted, "名前 % value" => "Alex")).to eq("Alex/Alex/%{value}/%Alex/value")
    expect(unrelated.reload.input_json).to eq("source_column" => "value")
    expect(unreferenced.reload.input_json).to eq("source_column" => "value_suffix")

    get "/transform_maps/#{second_map.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("transformations").first.fetch("input_json")).to eq(formatted.input_json)
  end

  it "updates unused declared template sources without changing literal text" do
    rule = add_rule("FormatStringTransformer", { "source_columns" => ["value"], "format" => "value %%{value}" })

    patch "/columns/#{source_column.id}", params: { column: { name: "unused{source}" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(rule.reload.input_json).to eq("source_columns" => ["unused{source}"], "format" => "value %%{value}")
    expect(transformed_value(rule, "unused{source}" => "Alex")).to eq("value %{value}")
  end

  it "rolls back the column and earlier rule updates if a template cannot use the new name" do
    copy = add_rule("CopyTransformer", { "source_column" => "value" })
    second_output = output_type.columns.create!(name: "formatted", position: 1)
    formatted = add_rule("FormatStringTransformer", { "source_columns" => ["value"], "format" => "%{value}" }, target: second_output)
    original_copy = copy.attributes
    original_format = formatted.attributes

    patch "/columns/#{source_column.id}", params: { column: { name: "invalid{name}", description: "Must roll back" } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("name")
    expect(source_column.reload.name).to eq("value")
    expect(source_column.description).to be_nil
    expect(copy.reload.attributes).to eq(original_copy)
    expect(formatted.reload.attributes).to eq(original_format)
  end

  it "leaves references unchanged when the new name is already taken" do
    input_type.columns.create!(name: "taken", position: 1)
    rule = add_rule("CopyTransformer", { "source_column" => "value" })

    patch "/columns/#{source_column.id}", params: { column: { name: "taken" } }, as: :json

    expect(response).to have_http_status(422)
    expect(source_column.reload.name).to eq("value")
    expect(rule.reload.input_json).to eq("source_column" => "value")
  end

  it "rejects moving and renaming a referenced source into a different file type" do
    rule = add_rule("CopyTransformer", { "source_column" => "value" })

    patch "/columns/#{source_column.id}", params: { column: { name: "moved", file_type_id: output_type.id } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("file_type")
    expect(source_column.reload.name).to eq("value")
    expect(source_column.file_type_id).to eq(input_type.id)
    expect(rule.reload.input_json).to eq("source_column" => "value")
  end

  it "keeps output targets linked by ID when an output column is renamed" do
    rule = add_rule("CopyTransformer", { "source_column" => "value" })

    patch "/columns/#{output_column.id}", params: { column: { name: "renamed result" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(rule.reload.output_column_id).to eq(output_column.id)
    expect(rule.input_json).to eq("source_column" => "value")
    expect(transformed_value(rule, "value" => "Alex")).to eq("Alex")
  end

  def add_rule(processor, settings, map: mapping, target: output_column)
    map.transformations.create!(output_column: target, input_json: settings,
                                column_transformer: ColumnTransformer.find_by!(processor_class: processor))
  end

  def transformed_value(rule, values)
    rule.reload
    source = CSV::Row.new(values.keys, values.values)
    destination = CSV::Row.new([rule.output_column.name], [nil])
    expect(rule.column_transformer.get_transformer(rule).transform(source, destination)).to be_nil
    destination[rule.output_column.name]
  end
end
