require "rails_helper"

RSpec.describe "Transform maps", type: :request do
  let(:input_type) { FileType.create!(name: "Customer import") }
  let(:output_type) { FileType.create!(name: "Customer export") }
  let(:mapping) do
    TransformMap.create!(name: "Customer conversion", input_file_type: input_type, output_file_type: output_type)
  end
  let(:transformation) do
    input_type.columns.create!(name: "email", position: 0)
    output_column = output_type.columns.create!(name: "email", position: 0)
    Transformation.create!(transform_map: mapping, output_column: output_column,
                           column_transformer: FactoryBot.create(:column_transformer),
                           input_json: { "name" => "email" })
  end

  it "creates a map from permitted fields" do
    expect do
      post "/transform_maps", params: { transform_map: {
        name: "Customer conversion", description: "Copy customer fields",
        input_file_type_id: input_type.id, output_file_type_id: output_type.id, id: -1,
      } }, as: :json
    end.to change(TransformMap, :count).by(1)

    expect(response).to have_http_status(:created)
    saved = TransformMap.find(response.parsed_body.fetch("id"))
    expect(saved.id).not_to eq(-1)
    expect(response.parsed_body).to eq(
      "id" => saved.id, "name" => "Customer conversion", "description" => "Copy customer fields",
      "input_file_type_id" => input_type.id, "output_file_type_id" => output_type.id,
    )
  end

  it "returns status 422 for an invalid reference without saving a map" do
    expect do
      post "/transform_maps", params: { transform_map: {
        name: "Invalid map", input_file_type_id: 0, output_file_type_id: output_type.id,
      } }, as: :json
    end.not_to change(TransformMap, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("input_file_type")
  end

  describe "creation with nested transformations" do
    let(:catalog) { FactoryBot.create(:column_transformer) }
    let(:first_rule) do
      { output_column_id: output_columns.first.id, column_transformer_id: catalog.id, input_json: { name: "email" } }
    end
    let(:second_rule) do
      { output_column_id: output_columns.second.id, column_transformer_id: catalog.id, input_json: { name: "phone" } }
    end
    let(:output_columns) do
      ["contact_email", "contact_phone", "optional_note"].each_with_index.map do |name, position|
        output_type.columns.create!(name: name, position: position)
      end
    end
    let(:payload) do
      { name: "Nested conversion", input_file_type_id: input_type.id, output_file_type_id: output_type.id }
    end

    before do
      input_type.columns.create!(name: "email", position: 0)
      input_type.columns.create!(name: "phone", position: 1)
      output_columns
      catalog
    end

    it "creates multiple transformations, ignores supplied identities, and allows unmapped output columns" do
      rules = [first_rule.merge(id: -1, transform_map_id: -1), second_rule]

      expect do
        post "/transform_maps", params: { transform_map: payload.merge(transformations: rules) }, as: :json
      end.to change(TransformMap, :count).by(1).and change(Transformation, :count).by(2)

      expect(response).to have_http_status(:created)
      saved = TransformMap.find(response.parsed_body.fetch("id"))
      expect(saved.transformations.pluck(:output_column_id, :column_transformer_id, :input_json)).to eq([
        [output_columns.first.id, catalog.id, { "name" => "email" }],
        [output_columns.second.id, catalog.id, { "name" => "phone" }],
      ])
      expect(saved.transformations.first.id).not_to eq(-1)
      expect(saved.transformations.pluck(:transform_map_id)).to eq([saved.id, saved.id])
      expect(saved.transformations.where(output_column: output_columns.last)).not_to exist
    end

    {
      "duplicate output target" => [{ output_column_id: :first_output }, "output_column_id"],
      "missing source column" => [{ input_json: { name: "missing" } }, "input_json"],
      "invalid schema configuration" => [{ input_json: { name: 123 } }, "input_json"],
      "missing transformer" => [{ column_transformer_id: 0 }, "column_transformer"],
      "missing output column" => [{ output_column_id: 0 }, "output_column"],
    }.each do |description, (attributes, field)|
      it "rolls back the map and earlier transformations for a #{description}" do
        invalid_rule = second_rule.merge(attributes)
        invalid_rule[:output_column_id] = output_columns.first.id if invalid_rule[:output_column_id] == :first_output

        expect do
          post "/transform_maps", params: { transform_map: payload.merge(transformations: [first_rule, invalid_rule]) }, as: :json
        end.not_to change { [TransformMap.count, Transformation.count] }

        expect(response).to have_http_status(422)
        expect(response.parsed_body.fetch("errors")).to have_key("transformations[1].#{field}")
      end
    end

    it "rejects a target from another file type and rolls back the entire map" do
      invalid_rule = second_rule.merge(output_column_id: input_type.columns.first.id)

      expect do
        post "/transform_maps", params: { transform_map: payload.merge(transformations: [first_rule, invalid_rule]) }, as: :json
      end.not_to change { [TransformMap.count, Transformation.count] }

      expect(response).to have_http_status(422)
      expect(response.parsed_body.fetch("errors")).to have_key("transformations[1].output_column")
    end

    { "object" => {}, "NULL" => nil, "non-object item" => ["invalid"] }.each do |description, transformations|
      it "returns JSON status 400 and rolls back the map for a malformed transformation #{description}" do
        expect do
          post "/transform_maps", params: { transform_map: payload.merge(transformations: transformations) }, as: :json
        end.not_to change { [TransformMap.count, Transformation.count] }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to eq("error" => "transformations must be an array of objects")
      end
    end

    it "accepts an empty transformation array" do
      post "/transform_maps", params: { transform_map: payload.merge(transformations: []) }, as: :json

      expect(response).to have_http_status(:created)
      expect(TransformMap.find(response.parsed_body.fetch("id")).transformations).to be_empty
    end
  end

  it "returns JSON status 400 when the required payload is missing" do
    expect do
      post "/transform_maps", params: {}, as: :json
    end.not_to change(TransformMap, :count)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to include("error" => a_kind_of(String))
  end

  it "lists maps by ID with their own transformation lists" do
    transformation
    empty_map = TransformMap.create!(name: "Alternative", input_file_type: input_type, output_file_type: output_type)

    get "/transform_maps", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |item| item.fetch("id") }).to eq([mapping.id, empty_map.id])
    expect(response.parsed_body.first.fetch("transformations")).to eq([
      {
        "id" => transformation.id, "transform_map_id" => mapping.id,
        "output_column_id" => transformation.output_column_id,
        "column_transformer_id" => transformation.column_transformer_id, "input_json" => { "name" => "email" },
      },
    ])
    expect(response.parsed_body.last.fetch("transformations")).to eq([])
    expect(response.parsed_body.first.keys).to match_array(
      ["id", "name", "description", "input_file_type_id", "output_file_type_id", "transformations"],
    )
  end

  it "returns the requested map including its transformations" do
    transformation

    get "/transform_maps/#{mapping.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "id" => mapping.id, "name" => "Customer conversion", "description" => nil,
      "input_file_type_id" => input_type.id, "output_file_type_id" => output_type.id,
      "transformations" => [{
        "id" => transformation.id, "transform_map_id" => mapping.id,
        "output_column_id" => transformation.output_column_id,
        "column_transformer_id" => transformation.column_transformer_id, "input_json" => { "name" => "email" },
      }],
    )
  end

  it "updates the map's configuration" do
    patch "/transform_maps/#{mapping.id}", params: { transform_map: {
      name: "Updated", description: "New description",
      input_file_type_id: output_type.id, output_file_type_id: input_type.id,
    } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(mapping.reload.name).to eq("Updated")
    expect(mapping.description).to eq("New description")
    expect(mapping.input_file_type_id).to eq(output_type.id)
    expect(mapping.output_file_type_id).to eq(input_type.id)
  end

  it "rejects changing the output file type when transformations still target the original type" do
    transformation

    patch "/transform_maps/#{mapping.id}", params: { transform_map: { output_file_type_id: input_type.id } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("output_file_type")
    expect(mapping.reload.output_file_type_id).to eq(output_type.id)
  end

  it "deletes a map and its transformations while retaining file types and columns" do
    transformation
    column_id = transformation.output_column_id

    expect do
      delete "/transform_maps/#{mapping.id}", as: :json
    end.to change(TransformMap, :count).by(-1).and change(Transformation, :count).by(-1)

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
    expect(FileType.exists?(input_type.id)).to be true
    expect(Column.exists?(column_id)).to be true
  end

  [:get, :patch, :delete].each do |verb|
    it "returns a JSON 404 when #{verb} targets a nonexistent map" do
      public_send(verb, "/transform_maps/0", params: { transform_map: { name: "missing" } })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
    end
  end
end
