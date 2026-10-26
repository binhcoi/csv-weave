require "rails_helper"
require_relative "../support/bulk_rule_examples"

RSpec.describe "Transformations", type: :request do
  let(:input_type) { FileType.create!(name: "Customer import") }
  let(:output_type) { FileType.create!(name: "Customer export") }
  let(:mapping) do
    TransformMap.create!(name: "Customer conversion", input_file_type: input_type, output_file_type: output_type)
  end
  let(:column) { output_type.columns.create!(name: "email", position: 0) }
  let(:other_column) { output_type.columns.create!(name: "customer_id", position: 1) }
  let(:catalog) { FactoryBot.create(:column_transformer) }
  let(:create_rows) do
    [column, other_column].map do |target|
      { transform_map_id: mapping.id, output_column_id: target.id,
        column_transformer_id: catalog.id, input_json: { "source_column" => target.name } }
    end
  end
  let(:invalid_row) { create_rows.last.merge(input_json: { "source_column" => 123 }) }
  let(:transformation) { Transformation.create!(create_rows.first) }

  before do
    ["email", "customer_id", "updated_source"].each_with_index do |name, position|
      input_type.columns.create!(name: name, position: position)
    end
  end

  it "creates a transformation from permitted fields" do
    expect do
      post "/transformations", params: { transformation: create_rows.first.merge(id: -1) }, as: :json
    end.to change(Transformation, :count).by(1)

    expect(response).to have_http_status(:created)
    saved = Transformation.find(response.parsed_body.fetch("id"))
    expect(saved.id).not_to eq(-1)
    expect(response.parsed_body).to eq(
      "id" => saved.id, "transform_map_id" => mapping.id, "output_column_id" => column.id,
      "column_transformer_id" => catalog.id, "input_json" => { "source_column" => "email" },
    )
  end

  it "returns schema errors with status 422 instead of saving invalid JSON parameters" do
    expect do
      post "/transformations", params: { transformation: invalid_row }, as: :json
    end.not_to change(Transformation, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").fetch("input_json").join).to include("/source_column")
  end

  it "rejects a source that exists only in the output file type" do
    other_column.update!(name: "output_only")

    expect do
      post "/transformations", params: { transformation: create_rows.last }, as: :json
    end.not_to change(Transformation, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body).to eq(
      "errors" => { "input_json" => ['source column "output_only" does not exist in the map\'s input file type'] },
    )
  end

  it "rejects updates to a nonexistent source without changing the saved rule" do
    patch "/transformations/#{transformation.id}", params: {
      transformation: { input_json: { source_column: "missing_source" } },
    }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").fetch("input_json").join).to include('"missing_source"')
    expect(transformation.reload.input_json).to eq("source_column" => "email")
  end

  it "rolls back bulk creation when a later source does not exist" do
    rows = [create_rows.first, create_rows.last.merge(input_json: { source_column: "missing_source" })]

    expect do
      post "/transformations/bulk", params: { transformations: rows }, as: :json
    end.not_to change(Transformation, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").first).to eq(
      "index" => 1,
      "errors" => { "input_json" => ['source column "missing_source" does not exist in the map\'s input file type'] },
    )
  end

  it "lists only transformations belonging to the requested map" do
    transformation
    other_map = TransformMap.create!(name: "Other map", input_file_type: input_type, output_file_type: output_type)
    Transformation.create!(create_rows.last.merge(transform_map_id: other_map.id))

    get "/transformations", params: { transform_map_id: mapping.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([{
      "id" => transformation.id, "transform_map_id" => mapping.id, "output_column_id" => column.id,
      "column_transformer_id" => catalog.id, "input_json" => { "source_column" => "email" },
    }])
  end

  it "returns the requested transformation" do
    get "/transformations/#{transformation.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "id" => transformation.id, "transform_map_id" => mapping.id, "output_column_id" => column.id,
      "column_transformer_id" => catalog.id, "input_json" => { "source_column" => "email" },
    )
  end

  it "updates permitted configuration fields without changing the record ID" do
    patch "/transformations/#{transformation.id}", params: { transformation: {
      output_column_id: other_column.id, input_json: { "source_column" => "customer_id" }, id: -1,
    } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(transformation.reload.output_column_id).to eq(other_column.id)
    expect(transformation.input_json).to eq("source_column" => "customer_id")
    expect(response.parsed_body.fetch("id")).to eq(transformation.id)
  end

  it "rejects invalid updates without clearing saved JSON parameters" do
    patch "/transformations/#{transformation.id}", params: { transformation: { input_json: nil } }, as: :json

    expect(response).to have_http_status(422)
    expect(transformation.reload.input_json).to eq("source_column" => "email")
  end

  it "rejects an output column that belongs to another file type" do
    wrong_column = input_type.columns.create!(name: "wrong", position: 3)

    post "/transformations", params: { transformation: create_rows.first.merge(output_column_id: wrong_column.id) }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("output_column")
    expect(Transformation.count).to eq(0)
  end

  it "prevents moving a targeted column to a different file type" do
    transformation

    patch "/columns/#{column.id}", params: { column: { file_type_id: input_type.id } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("file_type")
    expect(column.reload.file_type_id).to eq(output_type.id)
  end

  it "deletes the transformation while retaining its map, column, and catalog entry" do
    transformation
    expect do
      delete "/transformations/#{transformation.id}", as: :json
    end.to change(Transformation, :count).by(-1)

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
    expect(TransformMap.exists?(mapping.id)).to be true
    expect(Column.exists?(column.id)).to be true
    expect(ColumnTransformer.exists?(catalog.id)).to be true
  end

  [:get, :patch, :delete].each do |verb|
    it "returns a JSON 404 when #{verb} targets a missing transformation" do
      public_send(verb, "/transformations/0", params: { transformation: { input_json: nil } })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
    end
  end

  include_examples "atomic rule bulk writes", "/transformations", :transformations, Transformation

  it "rolls back bulk updates when a copy source is NULL even without a catalog schema" do
    catalog.update!(input_schema: nil)
    first, second = bulk_records

    patch "/transformations/bulk", params: { transformations: [
      { id: first.id, input_json: replacement_input }, { id: second.id, input_json: nil },
    ] }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").first.fetch("index")).to eq(1)
    expect(first.reload.input_json).to eq("source_column" => "email")
    expect(second.reload.input_json).to eq("source_column" => "customer_id")
  end
end
