require "rails_helper"

RSpec.describe "Columns", type: :request do
  let(:file_type) { FileType.create!(name: "Customer import") }
  let(:column) { file_type.columns.create!(name: "email", position: 0) }

  it "creates a column with permitted fields and returns status 201" do
    expect do
      post "/columns", params: { column: {
        file_type_id: file_type.id, name: "email", description: "Contact email", position: 0, id: -1,
      } }, as: :json
    end.to change(Column, :count).by(1)

    expect(response).to have_http_status(:created)
    saved = Column.find(response.parsed_body.fetch("id"))
    expect(saved.id).not_to eq(-1)
    expect(saved.name).to eq("email")
    expect(response.parsed_body).to eq(
      "id" => saved.id, "file_type_id" => file_type.id, "name" => "email",
      "description" => "Contact email", "position" => 0,
    )
  end

  it "returns model errors as status 422 without creating a column" do
    expect do
      post "/columns", params: { column: { file_type_id: file_type.id, name: "email", position: -1 } }, as: :json
    end.not_to change(Column, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("position")
  end

  it "lists only the requested file type's columns in position order" do
    later = file_type.columns.create!(name: "email", position: 3)
    first = file_type.columns.create!(name: "customer_id", position: 0)
    other_type = FileType.create!(name: "Other import")
    other_type.columns.create!(name: "excluded", position: 0)

    get "/columns", params: { file_type_id: file_type.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([
      { "id" => first.id, "file_type_id" => file_type.id, "name" => "customer_id",
        "description" => nil, "position" => 0 },
      { "id" => later.id, "file_type_id" => file_type.id, "name" => "email",
        "description" => nil, "position" => 3 },
    ])
  end

  it "returns the requested column as JSON" do
    get "/columns/#{column.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "id" => column.id, "file_type_id" => file_type.id, "name" => "email",
      "description" => nil, "position" => 0,
    )
  end

  it "updates permitted fields while keeping the record ID" do
    other_type = FileType.create!(name: "Other import")
    patch "/columns/#{column.id}", params: { column: {
      file_type_id: other_type.id, name: "contact_email", position: 2, id: -1,
    } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(column.reload.name).to eq("contact_email")
    expect(column.position).to eq(2)
    expect(column.file_type_id).to eq(other_type.id)
    expect(response.parsed_body.fetch("id")).to eq(column.id)
  end

  it "returns status 422 without persisting an invalid update" do
    patch "/columns/#{column.id}", params: { column: { name: "", position: 2 } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("name")
    expect(column.reload.name).to eq("email")
    expect(column.position).to eq(0)
  end

  [:get, :patch].each do |verb|
    it "returns a JSON 404 when #{verb} targets a nonexistent column" do
      public_send(verb, "/columns/0", params: { column: { name: "missing" } })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
    end
  end

  it "does not expose column deletion" do
    column
    expect do
      delete "/columns/#{column.id}", as: :json
    end.not_to change(Column, :count)

    expect(response).to have_http_status(:not_found)
  end
end
