require "rails_helper"

RSpec.describe "File types", type: :request do
  describe "POST /file_types" do
    it "creates a file type and returns its public fields as JSON with status 201" do
      expect do
        post "/file_types", params: {
          file_type: { name: "Customer import", description: "Incoming customer CSV" },
        }, as: :json
      end.to change(FileType, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.media_type).to eq("application/json")
      file_type = FileType.find(response.parsed_body.fetch("id"))
      expect(response.parsed_body).to eq(
        "id" => file_type.id,
        "name" => "Customer import",
        "description" => "Incoming customer CSV",
      )
      expect(file_type.name).to eq("Customer import")
      expect(file_type.description).to eq("Incoming customer CSV")
    end

    # Name validation cases live in the model specs; one invalid request covers the HTTP contract.
    it "returns field errors with status 422 without saving an invalid file type" do
      expect do
        post "/file_types", params: { file_type: { name: "" } }, as: :json
      end.not_to change(FileType, :count)

      expect(response).to have_http_status(422)
      expect(response.parsed_body).to match("errors" => { "name" => [a_kind_of(String)] })
    end

    it "ignores client-supplied IDs and nested columns" do
      expect do
        post "/file_types", params: {
          file_type: {
            name: "Customer import",
            id: -1,
            columns: [{ name: "email", position: 0 }],
          },
        }, as: :json
      end.not_to change(Column, :count)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch("id")).not_to eq(-1)
    end

    it "returns status 400 when the required request payload is missing" do
      expect do
        post "/file_types", params: {}, as: :json
      end.not_to change(FileType, :count)

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /file_types" do
    it "returns an empty JSON array when there are no file types" do
      get "/file_types", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "returns file types in ID order with their own columns and only public fields" do
      first_type = FileType.create!(name: "Zulu import", description: "Incoming customer CSV")
      second_type = FileType.create!(name: "Alpha export")
      column = first_type.columns.create!(name: "email", description: "Contact email", position: 0)

      get "/file_types", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([
        {
          "id" => first_type.id,
          "name" => "Zulu import",
          "description" => "Incoming customer CSV",
          "columns" => [
            { "id" => column.id, "name" => "email", "description" => "Contact email", "position" => 0 },
          ],
        },
        {
          "id" => second_type.id,
          "name" => "Alpha export",
          "description" => nil,
          "columns" => [],
        },
      ])
    end
  end

  describe "GET /file_types/:id" do
    it "returns the requested file type with its own columns and only public fields" do
      file_type = FileType.create!(name: "Customer import", description: "Incoming customer CSV")
      column = file_type.columns.create!(name: "email", description: "Contact email", position: 0)
      other_type = FileType.create!(name: "Other file type")
      other_type.columns.create!(name: "private_column", position: 0)

      get "/file_types/#{file_type.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "id" => file_type.id,
        "name" => "Customer import",
        "description" => "Incoming customer CSV",
        "columns" => [
          { "id" => column.id, "name" => "email", "description" => "Contact email", "position" => 0 },
        ],
      )
    end

    it "returns a JSON error with status 404 for a nonexistent file type" do
      missing_id = FileType.maximum(:id).to_i + 1

      get "/file_types/#{missing_id}", as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "File type not found")
    end
  end
end
