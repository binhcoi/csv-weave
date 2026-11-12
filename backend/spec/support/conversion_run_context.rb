require "stringio"

# Input "Orders" (name required, amount) -> output "Export" (name copied, total integer-parsed and required).
RSpec.shared_context "conversion run records" do
  let(:input_type) { FileType.create!(name: "Orders") }
  let(:output_type) { FileType.create!(name: "Export") }
  let(:required) { ColumnValidator.create!(processor_class: "RequiredValidator", description: "Required") }
  let(:copy) { ColumnTransformer.create!(processor_class: "CopyTransformer", description: "Copy") }
  let(:integer) { ColumnTransformer.create!(processor_class: "IntegerParseTransformer", description: "Integer") }
  let(:transform_map) do
    map = TransformMap.create!(name: "Orders to export", input_file_type: input_type, output_file_type: output_type)
    input_type.columns.create!(name: "name", position: 0).validations.create!(column_validator: required)
    input_type.columns.create!(name: "amount", position: 1)
    out_name = output_type.columns.create!(name: "name", position: 0)
    out_total = output_type.columns.create!(name: "total", position: 1)
    out_total.validations.create!(column_validator: required)
    map.transformations.create!(output_column: out_name, column_transformer: copy, input_json: { "source_column" => "name" })
    map.transformations.create!(output_column: out_total, column_transformer: integer,
                                input_json: { "source_column" => "amount" })
    map
  end

  def upload(content, file_type: input_type)
    DataFile.create!(file_type: file_type, file: {
      io: StringIO.new(content), filename: "orders.csv", content_type: "text/csv", identify: false,
    })
  end

  def purge_conversion_files
    ConversionRun.find_each { |run| [run.output, run.error_report].each { |file| file.purge if file.attached? } }
    DataFile.find_each { |record| record.file.purge }
  end
end
