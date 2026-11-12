require "rails_helper"
require "tempfile"

RSpec.describe DataFileUpload do
  let(:file_type) { FileType.create!(name: "Orders") }
  let(:tempfile) do
    Tempfile.new("data-file-upload").tap { |io| io.write("id\nA1001\n"); io.rewind }
  end
  let(:upload) { ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: "orders.csv", type: "text/csv") }
  let(:storage) { ActiveStorage::Blob.services.fetch("test") }

  after do
    DataFile.find_each { |record| record.file.purge }
    tempfile.close!
  end

  it "uploads the bytes once and commits a downloadable attachment" do
    expect(storage).to receive(:upload).once.and_call_original

    record = described_class.create!(file_type_id: file_type.id, upload: upload)

    expect(record.reload.file.download).to eq("id\nA1001\n")
  end

  it "rolls back metadata and removes partial bytes when storage fails" do
    key = nil
    allow(storage).to receive(:upload).and_wrap_original do |original, blob_key, io, **options|
      key = blob_key
      original.call(blob_key, io, **options)
      raise IOError, "storage failed"
    end

    expect do
      expect { described_class.create!(file_type_id: file_type.id, upload: upload) }.to raise_error(IOError, "storage failed")
    end.not_to change { [DataFile.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count] }

    expect(key).not_to be_nil
    expect(storage.exist?(key)).to be false
  end

  it "removes uploaded bytes if saving the owner fails" do
    record = DataFile.new(file_type: file_type)
    allow(DataFile).to receive(:new).and_return(record)
    allow(record).to receive(:save!).and_raise(ActiveRecord::RecordNotSaved, "save failed")
    key = nil
    allow(storage).to receive(:upload).and_wrap_original do |original, blob_key, io, **options|
      key = blob_key
      original.call(blob_key, io, **options)
    end

    expect do
      expect { described_class.create!(file_type_id: file_type.id, upload: upload) }
        .to raise_error(ActiveRecord::RecordNotSaved, "save failed")
    end.not_to change { [DataFile.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count] }

    expect(key).not_to be_nil
    expect(storage.exist?(key)).to be false
  end
end
