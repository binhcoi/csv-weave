require "rails_helper"
require "stringio"

RSpec.describe "Data files", type: :request do
  let(:file_type) { FileType.create!(name: "Orders") }
  let(:content) { "order_id,name\r\nA1001,\"李, Alex\nMorgan\"\r\n" }
  let(:upload) { Rack::Test::UploadedFile.new(StringIO.new(content), "application/octet-stream", true, original_filename: "orders.csv") }

  after { DataFile.find_each { |record| record.file.purge } }

  it "uploads, reads metadata, and downloads the original bytes through storage redirects" do
    post "/data_files", params: { data_file: { file_type_id: file_type.id, file: upload, id: -1, key: "ignored" } }

    expect(response).to have_http_status(:created)
    metadata = response.parsed_body
    record = DataFile.find(metadata.fetch("id"))
    expect(record.id).not_to eq(-1)
    expect(metadata).to eq(
      "id" => record.id, "file_type_id" => file_type.id, "filename" => "orders.csv", "content_type" => "text/csv",
      "byte_size" => content.bytesize, "created_at" => record.created_at.as_json,
      "download_url" => "http://www.example.com/data_files/#{record.id}/download",
    )
    expect(response.location).to eq("http://www.example.com/data_files/#{record.id}")

    get "/data_files/#{record.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(metadata)

    get metadata.fetch("download_url")
    expect(response).to have_http_status(:found)
    follow_redirect!
    expect(response).to have_http_status(:found)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("Content-Disposition")).to include("attachment", "orders.csv")
    expect(response.body.b).to eq(content.b)
  end

  it "stores malformed CSV and invalid encoding unchanged for a later validation operation" do
    raw = "\"unfinished,\xFF\n".b
    file = Rack::Test::UploadedFile.new(StringIO.new(raw), "text/plain", true, original_filename: "unvalidated.csv")

    post "/data_files", params: { data_file: { file_type_id: file_type.id, file: file } }

    expect(response).to have_http_status(:created)
    record = DataFile.find(response.parsed_body.fetch("id"))
    expect(record.file.download).to eq(raw)
  end

  it "rejects an unknown file type without creating a file, attachment, or blob" do
    expect do
      post "/data_files", params: { data_file: { file_type_id: 999_999, file: upload } }
    end.not_to change { [DataFile.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count] }

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("file_type")
  end

  it "rejects oversized uploads before hashing or storing them" do
    stub_const("DataFile::MAX_UPLOAD_BYTES", 1)
    expect(DataFileUpload).not_to receive(:create!)

    post "/data_files", params: { data_file: { file_type_id: file_type.id, file: upload } }

    expect(response).to have_http_status(413)
    expect(response.parsed_body).to eq("error" => "file exceeds the 1 byte upload limit")
  end

  it "returns 400 for a missing upload" do
    post "/data_files", params: { data_file: { file_type_id: file_type.id } }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to have_key("error")
  end

  it "rejects a file path or signed blob ID supplied instead of a multipart upload" do
    post "/data_files", params: { data_file: { file_type_id: file_type.id, file: "/etc/passwd" } }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "file must be a multipart upload")
  end

  it "rejects malformed file type IDs instead of accepting their numeric prefix" do
    post "/data_files", params: { data_file: { file_type_id: "#{file_type.id}abc", file: upload } }

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "file_type_id must be a positive integer")
  end

  ["/data_files/0", "/data_files/0/download"].each do |path|
    it "returns JSON 404 for #{path}" do
      get path

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
    end
  end
end
