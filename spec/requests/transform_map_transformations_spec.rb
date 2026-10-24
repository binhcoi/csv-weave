require "rails_helper"

RSpec.describe "Transform-map bulk transformation changes", type: :request do
  let(:input_type) { FileType.create!(name: "Customer import") }
  let(:output_type) { FileType.create!(name: "Customer export") }
  let(:mapping) do
    TransformMap.create!(name: "Customer conversion", input_file_type: input_type, output_file_type: output_type)
  end
  let(:path) { "/transform_maps/#{mapping.id}/transformations" }
  let(:catalog) { FactoryBot.create(:column_transformer) }
  let(:columns) do
    ["contact_email", "contact_phone", "optional_note"].each_with_index.map do |name, position|
      output_type.columns.create!(name: name, position: position)
    end
  end
  let(:first_attributes) do
    { output_column_id: columns.first.id, column_transformer_id: catalog.id, input_json: { name: "email" } }
  end
  let(:second_attributes) do
    { output_column_id: columns.second.id, column_transformer_id: catalog.id, input_json: { name: "phone" } }
  end
  let(:rule) { mapping.transformations.create!(first_attributes) }

  before do
    ["email", "phone", "updated_source"].each_with_index do |name, position|
      input_type.columns.create!(name: name, position: position)
    end
    columns
    mapping
    catalog
  end

  it "replaces multiple transformations, retains other rules, and ignores supplied identities and map ownership" do
    first = rule
    second = mapping.transformations.create!(second_attributes)
    kept = mapping.transformations.create!(first_attributes.merge(output_column_id: columns.last.id))
    foreign_map = TransformMap.create!(name: "Other map", input_file_type: input_type, output_file_type: output_type)
    foreign_rule = foreign_map.transformations.create!(first_attributes)

    patch path, params: { remove_ids: [first.id, second.id], add: [
      first_attributes.merge(id: -1, transform_map_id: foreign_map.id, input_json: { name: "updated_source" }),
      second_attributes,
    ] }, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.map { |item| item.fetch("id") }).to eq(body.map { |item| item.fetch("id") }.sort)
    expect(body.map { |item| item.fetch("id") }).not_to include(-1, first.id, second.id, foreign_rule.id)
    expect(body.first.fetch("id")).to eq(kept.id)
    expect(body.map { |item| item.fetch("transform_map_id") }).to eq([mapping.id] * 3)
    expect(body.map { |item| item.fetch("output_column_id") }).to eq([columns.last.id, columns.first.id, columns.second.id])
    expect(body[1].fetch("input_json")).to eq("name" => "updated_source")
    expect(body.last.keys).to match_array(%w[id transform_map_id output_column_id column_transformer_id input_json])
    saved = mapping.transformations.reload.map do |record|
      record.attributes.slice("id", "transform_map_id", "output_column_id", "column_transformer_id", "input_json")
    end
    expect(saved).to eq(body)
    expect(Transformation.where(id: [first.id, second.id])).not_to exist
    expect(foreign_rule.reload.input_json).to eq("name" => "email")
    expect(Column.where(id: columns.map(&:id)).count).to eq(3)
    expect(ColumnTransformer.exists?(catalog.id)).to be true
  end

  it "accepts additions without removals and preserves arbitrary JSON allowed by the catalog" do
    catalog.update!(input_schema: nil)
    options = { name: "email", options: [1, { enabled: true }] }

    expect do
      patch path, params: { add: [first_attributes.merge(input_json: options), second_attributes] }, as: :json
    end.to change(Transformation, :count).by(2)

    expect(response).to have_http_status(:ok)
    expect(mapping.transformations.first.input_json).to eq(options.deep_stringify_keys)
    expect(mapping.transformations.pluck(:output_column_id)).to eq(columns.first(2).map(&:id))
  end

  it "accepts multiple removals without additions and retains the map and shared records" do
    ids = [rule.id, mapping.transformations.create!(second_attributes).id]

    expect do
      patch path, params: { remove_ids: ids }, as: :json
    end.to change(Transformation, :count).by(-2)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
    expect(Transformation.where(id: ids)).not_to exist
    expect(TransformMap.exists?(mapping.id)).to be true
    expect(Column.where(id: columns.map(&:id)).count).to eq(3)
    expect(ColumnTransformer.exists?(catalog.id)).to be true
  end

  [{}, { add: [], remove_ids: [] }].each do |payload|
    it "returns the current collection for empty operations #{payload.inspect}" do
      original = rule

      patch path, params: payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |item| item.fetch("id") }).to eq([original.id])
    end
  end

  {
    "invalid schema configuration" => [{ input_json: { name: 123 } }, "input_json"],
    "missing source" => [{ input_json: { name: "missing" } }, "input_json"],
    "nonexistent catalog" => [{ column_transformer_id: 0 }, "column_transformer"],
  }.each do |description, (attributes, field)|
    it "restores removals and rolls back earlier additions for a later #{description}" do
      original = rule

      expect do
        patch path, params: { remove_ids: [original.id], add: [
          first_attributes.merge(input_json: { name: "updated_source" }), second_attributes.merge(attributes),
        ] }, as: :json
      end.not_to change(Transformation, :count)

      expect(response).to have_http_status(422)
      expect(response.parsed_body.fetch("errors")).to have_key("add[1].#{field}")
      expect(mapping.transformations.reload.pluck(:id)).to eq([original.id])
      expect(original.reload.input_json).to eq("name" => "email")
    end
  end

  it "rolls back replacements when two additions target the same output column" do
    original = rule

    patch path, params: { remove_ids: [original.id], add: [first_attributes, first_attributes] }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("add[1].output_column_id")
    expect(mapping.transformations.reload.pluck(:id)).to eq([original.id])
  end

  it "rejects an output from another file type and restores removals and earlier additions" do
    original = rule
    foreign_column = input_type.columns.first

    patch path, params: { remove_ids: [original.id], add: [
      first_attributes, second_attributes.merge(output_column_id: foreign_column.id),
    ] }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("add[1].output_column")
    expect(mapping.transformations.reload.pluck(:id)).to eq([original.id])
    expect(foreign_column.transformations).to be_empty
  end

  ["missing", "foreign"].each do |kind|
    it "restores earlier removals when a later removal ID is #{kind}" do
      original = rule
      foreign_map = TransformMap.create!(name: "Other map", input_file_type: input_type, output_file_type: output_type)
      foreign_rule = foreign_map.transformations.create!(first_attributes)
      id = kind == "foreign" ? foreign_rule.id : Transformation.maximum(:id) + 1

      expect do
        patch path, params: { remove_ids: [original.id, id] }, as: :json
      end.not_to change(Transformation, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
      expect(Transformation.exists?(original.id)).to be true
      expect(Transformation.exists?(foreign_rule.id)).to be true
    end
  end

  it "returns JSON status 404 for a missing map" do
    expect do
      patch "/transform_maps/0/transformations", params: { add: [] }, as: :json
    end.not_to change(Transformation, :count)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "Record not found")
  end

  {
    "non-array additions" => { add: {} },
    "NULL additions" => { add: nil },
    "non-object additions" => { add: ["invalid"] },
    "non-array removal IDs" => { remove_ids: {} },
    "NULL removal IDs" => { remove_ids: nil },
    "non-integer removal IDs" => { remove_ids: ["1"] },
    "nonpositive removal IDs" => { remove_ids: [0] },
  }.each do |description, payload|
    it "returns JSON status 400 for #{description} before applying removals" do
      original = rule

      expect do
        patch path, params: { remove_ids: [original.id] }.merge(payload), as: :json
      end.not_to change(Transformation, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("error" => a_kind_of(String))
      expect(Transformation.exists?(original.id)).to be true
    end
  end

  it "rejects duplicate removal IDs before changing the collection" do
    original = rule

    patch path, params: { remove_ids: [original.id, original.id] }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "remove_ids must not contain duplicate IDs")
    expect(Transformation.exists?(original.id)).to be true
  end
end
