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
