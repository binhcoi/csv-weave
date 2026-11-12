RSpec.shared_context "validation records" do
  subject(:validation) do
    described_class.new(column: column, column_validator: column_validator)
  end

  let(:file_type) { FileType.create!(name: "Customer import") }
  let(:column) { Column.create!(file_type: file_type, name: "email", position: 0) }
  let(:column_validator) { FactoryBot.create(:column_validator) }
end
