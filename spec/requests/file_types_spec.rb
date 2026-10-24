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

  describe "PATCH /file_types/:id" do
    let(:file_type) { FileType.create!(name: "Customer import", description: "Original description") }

    it "updates name and description while ignoring IDs and nested columns" do
      column = file_type.columns.create!(name: "email", position: 0)

      expect do
        patch "/file_types/#{file_type.id}", params: { file_type: {
          name: "Customer export", description: "Updated description", id: -1,
          columns: [{ id: column.id, name: "ignored" }],
        } }, as: :json
      end.not_to change(FileType, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "id" => file_type.id, "name" => "Customer export", "description" => "Updated description",
      )
      expect(file_type.reload.name).to eq("Customer export")
      expect(file_type.description).to eq("Updated description")
      expect(column.reload.name).to eq("email")
    end

    it "preserves omitted attributes" do
      patch "/file_types/#{file_type.id}", params: { file_type: { name: "Renamed" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(file_type.reload.name).to eq("Renamed")
      expect(file_type.description).to eq("Original description")
    end

    it "clears the description when explicitly set to NULL" do
      patch "/file_types/#{file_type.id}", params: { file_type: { description: nil } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("description")).to be_nil
      expect(file_type.reload.description).to be_nil
      expect(file_type.name).to eq("Customer import")
    end

    it "returns field errors without persisting any part of an invalid update" do
      patch "/file_types/#{file_type.id}", params: {
        file_type: { name: "", description: "Should not persist" },
      }, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body).to match("errors" => { "name" => [a_kind_of(String)] })
      expect(file_type.reload.name).to eq("Customer import")
      expect(file_type.description).to eq("Original description")
    end

    it "returns JSON status 404 for a nonexistent file type" do
      patch "/file_types/0", params: { file_type: { name: "Missing" } }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
    end

    it "returns status 400 when the required payload is missing" do
      patch "/file_types/#{file_type.id}", params: {}, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("error" => a_kind_of(String))
      expect(file_type.reload.name).to eq("Customer import")
    end

    it "returns JSON status 400 for a malformed payload" do
      patch "/file_types/#{file_type.id}", params: { file_type: "invalid" }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("error" => a_kind_of(String))
      expect(file_type.reload.name).to eq("Customer import")
    end
  end

  describe "DELETE /file_types/:id" do
    let(:file_type) { FileType.create!(name: "Customer import") }

    it "deletes its columns and validations while retaining unrelated records and catalogs" do
      catalog = FactoryBot.create(:column_validator)
      columns = ["email", "phone"].each_with_index.map do |name, position|
        file_type.columns.create!(name: name, position: position)
      end
      rules = columns.map { |column| column.validations.create!(column_validator: catalog) }
      other_type = FileType.create!(name: "Other format")
      other_column = other_type.columns.create!(name: "email", position: 0)
      other_rule = other_column.validations.create!(column_validator: catalog)

      expect do
        delete "/file_types/#{file_type.id}", as: :json
      end.to change(FileType, :count).by(-1).and change(Column, :count).by(-2).and change(Validation, :count).by(-2)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(FileType.exists?(file_type.id)).to be false
      expect(Column.where(id: columns.map(&:id))).not_to exist
      expect(Validation.where(id: rules.map(&:id))).not_to exist
      expect(FileType.exists?(other_type.id)).to be true
      expect(Column.exists?(other_column.id)).to be true
      expect(Validation.exists?(other_rule.id)).to be true
      expect(ColumnValidator.exists?(catalog.id)).to be true
    end

    it "returns model errors before attempting to destroy columns used by transformations" do
      column = file_type.columns.create!(name: "email", position: 0)
      validation = column.validations.create!(column_validator: FactoryBot.create(:column_validator))
      mapping = TransformMap.create!(name: "Same-format copy", input_file_type: file_type, output_file_type: file_type)
      transformation = mapping.transformations.create!(output_column: column,
                                                       column_transformer: FactoryBot.create(:column_transformer),
                                                       input_json: { name: column.name })

      expect do
        delete "/file_types/#{file_type.id}", as: :json
      end.not_to change(FileType, :count)

      expect(response).to have_http_status(422)
      expect(response.parsed_body).to eq("errors" => { "base" => ["cannot delete a file type used by a transform map"] })
      expect(Column.exists?(column.id)).to be true
      expect(Validation.exists?(validation.id)).to be true
      expect(TransformMap.exists?(mapping.id)).to be true
      expect(Transformation.exists?(transformation.id)).to be true
    end

    it "returns JSON status 404 for a nonexistent file type" do
      delete "/file_types/0", as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
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
