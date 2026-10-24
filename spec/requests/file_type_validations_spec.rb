require "rails_helper"

RSpec.describe "File-type bulk validation changes", type: :request do
  let(:file_type) { FileType.create!(name: "Customer import") }
  let(:path) { "/file_types/#{file_type.id}/validations" }
  let(:column) { file_type.columns.create!(name: "email", position: 0) }
  let(:other_column) { file_type.columns.create!(name: "phone", position: 1) }
  let(:catalog) { FactoryBot.create(:column_validator) }
  let(:rule) { column.validations.create!(column_validator: catalog) }

  it "adds and removes multiple rules across columns and returns only this file type's rules in ID order" do
    first = rule
    second = other_column.validations.create!(column_validator: catalog)
    kept = column.validations.create!(column_validator: catalog)
    foreign_type = FileType.create!(name: "Other format")
    foreign_column = foreign_type.columns.create!(name: "email", position: 0)
    foreign_rule = foreign_column.validations.create!(column_validator: catalog)
    options = { "options" => { "enabled" => true, "values" => [1, { "label" => "example" }] } }

    expect do
      patch path, params: {
        remove_ids: [first.id, second.id],
        add: [
          { column_id: other_column.id, column_validator_id: catalog.id, input_json: nil, id: -1, file_type_id: foreign_type.id },
          { column_id: column.id, column_validator_id: catalog.id, input_json: options },
        ],
      }, as: :json
    end.not_to change(Column, :count)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.map { |item| item.fetch("id") }).to eq(body.map { |item| item.fetch("id") }.sort)
    expect(body.map { |item| item.fetch("column_id") }).to eq([column.id, other_column.id, column.id])
    expect(body.first.fetch("id")).to eq(kept.id)
    expect(body[1].fetch("input_json")).to be_nil
    expect(body.last.fetch("input_json")).to eq(options)
    expect(body.map { |item| item.fetch("id") }).not_to include(-1, first.id, second.id, foreign_rule.id)
    expect(body.last.keys).to match_array(%w[id column_id column_validator_id input_json])
    saved = Validation.where(id: body.map { |item| item.fetch("id") }).order(:id).map do |record|
      record.attributes.slice("id", "column_id", "column_validator_id", "input_json")
    end
    expect(saved).to eq(body)
    expect(Validation.where(id: [first.id, second.id])).not_to exist
    expect(Validation.exists?(foreign_rule.id)).to be true
    expect(ColumnValidator.exists?(catalog.id)).to be true
  end

  it "accepts additions without remove_ids and preserves omitted and scalar JSON parameters" do
    patch path, params: { add: [
      { column_id: column.id, column_validator_id: catalog.id },
      { column_id: other_column.id, column_validator_id: catalog.id, input_json: false },
    ] }, as: :json

    expect(response).to have_http_status(:ok)
    expect(column.validations.sole.input_json).to eq({})
    expect(other_column.validations.sole.input_json).to be false
  end

  it "accepts removals without add" do
    ids = [rule.id, other_column.validations.create!(column_validator: catalog).id]

    patch path, params: { remove_ids: ids }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
    expect(Validation.where(id: ids)).not_to exist
    expect(ColumnValidator.exists?(catalog.id)).to be true
  end

  it "returns the existing rules when both arrays are empty" do
    rule

    patch path, params: { add: [], remove_ids: [] }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |item| item.fetch("id") }).to eq([rule.id])
  end

  it "restores removals and earlier additions when a later rule fails schema validation" do
    catalog.update!(input_schema: {
      "type" => "object", "properties" => { "limit" => { "type" => "integer" } }, "required" => ["limit"],
    })
    original = column.validations.create!(column_validator: catalog, input_json: { limit: 1 })

    expect do
      patch path, params: { remove_ids: [original.id], add: [
        { column_id: column.id, column_validator_id: catalog.id, input_json: { limit: 2 } },
        { column_id: other_column.id, column_validator_id: catalog.id, input_json: { limit: "invalid" } },
      ] }, as: :json
    end.not_to change(Validation, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").fetch("add[1].input_json").join).to include("limit")
    expect(column.validations.reload.pluck(:id)).to eq([original.id])
    expect(original.reload.input_json).to eq("limit" => 1)
    expect(other_column.validations).to be_empty
  end

  it "rejects a nonexistent catalog entry and restores removed rules" do
    original = rule

    patch path, params: { remove_ids: [original.id], add: [
      { column_id: column.id, column_validator_id: 0 },
    ] }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("add[0].column_validator")
    expect(column.validations.reload.pluck(:id)).to eq([original.id])
  end

  ["missing", "foreign"].each do |kind|
    it "restores earlier removals when a later removal ID is #{kind}" do
      original = rule
      foreign_column = FileType.create!(name: "Other format").columns.create!(name: "email", position: 0)
      foreign_rule = foreign_column.validations.create!(column_validator: catalog)
      id = kind == "foreign" ? foreign_rule.id : Validation.maximum(:id) + 1

      expect do
        patch path, params: { remove_ids: [original.id, id] }, as: :json
      end.not_to change(Validation, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
      expect(Validation.exists?(original.id)).to be true
      expect(Validation.exists?(foreign_rule.id)).to be true
    end

    it "restores removals and earlier additions when a later target column is #{kind}" do
      original = rule
      foreign_column = FileType.create!(name: "Other format").columns.create!(name: "email", position: 0)
      id = kind == "foreign" ? foreign_column.id : Column.maximum(:id) + 1

      expect do
        patch path, params: { remove_ids: [original.id], add: [
          { column_id: column.id, column_validator_id: catalog.id },
          { column_id: id, column_validator_id: catalog.id },
        ] }, as: :json
      end.not_to change(Validation, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
      expect(column.validations.reload.pluck(:id)).to eq([original.id])
      expect(foreign_column.validations).to be_empty
    end
  end

  it "returns JSON status 404 for a missing file type" do
    expect do
      patch "/file_types/0/validations", params: { add: [] }, as: :json
    end.not_to change(Validation, :count)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "Record not found")
  end

  {
    "non-array additions" => { add: {} },
    "non-object additions" => { add: ["invalid"] },
    "non-array removal IDs" => { remove_ids: {} },
    "non-integer removal IDs" => { remove_ids: [{ id: 1 }] },
    "nonpositive removal IDs" => { remove_ids: [0] },
  }.each do |description, payload|
    it "returns JSON status 400 for #{description}" do
      original = rule

      expect do
        patch path, params: { remove_ids: [original.id] }.merge(payload), as: :json
      end.not_to change(Validation, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("error" => a_kind_of(String))
      expect(Validation.exists?(original.id)).to be true
    end
  end

  it "rejects duplicate removal IDs before deleting any rules" do
    original = rule

    patch path, params: { remove_ids: [original.id, original.id] }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "remove_ids must not contain duplicate IDs")
    expect(Validation.exists?(original.id)).to be true
  end

  it "restores removed rules when an addition omits its column ID" do
    original = rule

    patch path, params: { remove_ids: [original.id], add: [{ column_validator_id: catalog.id }] }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch("error")).to include("column_id")
    expect(Validation.exists?(original.id)).to be true
  end
end
