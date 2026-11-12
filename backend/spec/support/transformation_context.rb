RSpec.shared_context "transformation records" do
  subject(:transformation) do
    described_class.new(transform_map: transform_map, output_column: output_column,
                        column_transformer: column_transformer, input_json: { "source_column" => "email" })
  end

  let(:input_file_type) { FileType.create!(name: "Customer import") }
  let(:output_file_type) { FileType.create!(name: "Customer export") }
  let(:transform_map) do
    TransformMap.create!(name: "Customer conversion", input_file_type: input_file_type,
                         output_file_type: output_file_type)
  end
  let(:output_column) { Column.create!(file_type: output_file_type, name: "email", position: 0) }
  let(:column_transformer) { FactoryBot.create(:column_transformer) }

  before do
    ["email", "contact_email", "customer_id"].each_with_index do |name, position|
      input_file_type.columns.create!(name: name, position: position)
    end
  end
end
