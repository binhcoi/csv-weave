require "rails_helper"
require "stringio"

RSpec.describe DataFile, type: :model do
  let(:file_type) { FileType.create!(name: "Orders") }
  let(:attachment) { { io: StringIO.new("order_id\nA1001\n"), filename: "orders.csv", content_type: "text/csv", identify: false } }
  subject(:data_file) { described_class.new(file_type: file_type, file: attachment) }

  after { described_class.find_each { |record| record.file.purge } }

  it "requires an existing file type and an attachment" do
    record = described_class.new(file_type_id: 0)

    expect(record).not_to be_valid
    expect(record.errors.attribute_names).to contain_exactly(:file_type, :file)
  end

  it "allows an empty upload for later CSV validation" do
    data_file.file = attachment.merge(io: StringIO.new)

    expect(data_file).to be_valid
  end

  it "accepts the size limit and rejects one byte above it" do
    stub_const("DataFile::MAX_UPLOAD_BYTES", 5)
    data_file.file = attachment.merge(io: StringIO.new("12345"))
    expect(data_file).to be_valid

    data_file.file = attachment.merge(io: StringIO.new("123456"))
    expect(data_file).not_to be_valid
    expect(data_file.errors[:file]).to eq(["must be at most 5 bytes"])
  end

  it "rejects changing the assigned file type" do
    data_file.save!
    other_type = FileType.create!(name: "Customers")

    expect(data_file.update(file_type: other_type)).to be false
    expect(data_file.errors[:file_type]).to eq(["cannot change after upload"])
    expect(data_file.reload.file_type_id).to eq(file_type.id)
  end

  it "rejects replacing or clearing stored bytes through attachment assignment" do
    data_file.save!
    original_blob_id = data_file.file.blob.id

    data_file.file = attachment.merge(io: StringIO.new("replacement"))
    expect(data_file.save).to be false
    expect(data_file.errors[:file]).to include("cannot change after upload")
    expect(data_file.reload.file.blob.id).to eq(original_blob_id)

    data_file.file = nil
    expect(data_file.save).to be false
    expect(data_file.errors[:file]).to include("cannot change after upload")
    expect(data_file.reload.file.blob.id).to eq(original_blob_id)
  end

  it "blocks deleting a referenced file type before deleting its columns" do
    data_file.save!
    column = file_type.columns.create!(name: "order_id", position: 0)

    expect(file_type.destroy).to be false
    expect(file_type.errors[:base]).to eq(["cannot delete a file type used by a data file"])
    expect(Column.exists?(column.id)).to be true
    expect(data_file.reload.file).to be_attached
  end

  it "enforces the file type foreign key without model validation" do
    expect do
      described_class.transaction(requires_new: true) do
        described_class.insert_all!([{ file_type_id: 0 }])
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
