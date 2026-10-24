require "rails_helper"

RSpec.describe "File-type bulk column changes", type: :request do
  let(:file_type) { FileType.create!(name: "Customer import") }
  let(:path) { "/file_types/#{file_type.id}/columns" }
  let(:column) { file_type.columns.create!(name: "email", position: 0) }
  let(:catalog) { FactoryBot.create(:column_validator) }

  it "removes multiple columns and their rules, then adds columns using the freed names and positions" do
    first = column
    second = file_type.columns.create!(name: "country", position: 1)
    kept = file_type.columns.create!(name: "phone", position: 2)
    removed_rules = [first, second].map { |record| record.validations.create!(column_validator: catalog) }
    kept_rule = kept.validations.create!(column_validator: catalog)
    other_type = FileType.create!(name: "Other format")
    other_column = other_type.columns.create!(name: "email", position: 0)

    expect do
      patch path, params: {
        remove_ids: [first.id, second.id],
        add: [
          { name: "city", position: 5, description: "City", id: -1, file_type_id: other_type.id },
          { name: "email", position: 0 },
        ],
      }, as: :json
    end.to change(Validation, :count).by(-2)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.map { |item| item.fetch("name") }).to eq(["email", "phone", "city"])
    expect(body.map { |item| item.fetch("position") }).to eq([0, 2, 5])
    expect(body.map { |item| item.fetch("file_type_id") }).to eq([file_type.id] * 3)
    expect(body.last.fetch("description")).to eq("City")
    expect(body.last.keys).to match_array(%w[id file_type_id name description position])
    expect(body.map { |item| item.fetch("id") }).not_to include(-1, first.id, second.id)
    expect(file_type.columns.reload.pluck(:id)).to eq(body.map { |item| item.fetch("id") })
    expect(Validation.where(id: removed_rules.map(&:id))).not_to exist
    expect(Validation.exists?(kept_rule.id)).to be true
    expect(Column.exists?(other_column.id)).to be true
    expect(ColumnValidator.exists?(catalog.id)).to be true
  end

  it "accepts additions without remove_ids" do
    patch path, params: { add: [{ name: "email", position: 0 }, { name: "phone", position: 1 }] }, as: :json

    expect(response).to have_http_status(:ok)
    expect(file_type.columns.pluck(:name)).to eq(["email", "phone"])
  end

  it "accepts removals without add" do
    ids = [column.id, file_type.columns.create!(name: "phone", position: 1).id]

    patch path, params: { remove_ids: ids }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
    expect(file_type.columns.reload).to be_empty
  end

  it "returns the existing columns when both arrays are empty" do
    column

    patch path, params: { add: [], remove_ids: [] }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |item| item.fetch("id") }).to eq([column.id])
  end

  it "restores removals and their validations when a later addition fails" do
    rule = column.validations.create!(column_validator: catalog)

    expect do
      patch path, params: {
        remove_ids: [column.id],
        add: [{ name: "city", position: 1 }, { name: "invalid", position: -1 }],
      }, as: :json
    end.not_to change { [Column.count, Validation.count] }

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("add[1].position")
    expect(file_type.columns.reload.pluck(:id)).to eq([column.id])
    expect(Validation.exists?(rule.id)).to be true
  end

  ["missing", "foreign"].each do |kind|
    it "restores earlier removals when a later removal ID is #{kind}" do
      rule = column.validations.create!(column_validator: catalog)
      other_column = FileType.create!(name: "Other format").columns.create!(name: "email", position: 0)
      id = kind == "foreign" ? other_column.id : Column.maximum(:id) + 1

      expect do
        patch path, params: {
          remove_ids: [column.id, id], add: [{ name: "city", position: 1 }],
        }, as: :json
      end.not_to change { [Column.count, Validation.count] }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
      expect(Column.exists?(column.id)).to be true
      expect(Column.exists?(other_column.id)).to be true
      expect(Validation.exists?(rule.id)).to be true
    end
  end

  it "returns JSON status 404 for a missing file type" do
    expect do
      patch "/file_types/0/columns", params: { add: [{ name: "email", position: 0 }] }, as: :json
    end.not_to change(Column, :count)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "Record not found")
  end

  ["source", "output"].each do |role|
    it "restores earlier removals when a later column is used as a transformation #{role}" do
      column
      unused = file_type.columns.create!(name: "unused", position: 1)
      rule = unused.validations.create!(column_validator: catalog)
      other_type = FileType.create!(name: "Other format")
      other_column = other_type.columns.create!(name: "email", position: 0)
      input_type, output_type, target = if role == "source"
        [file_type, other_type, other_column]
      else
        [other_type, file_type, column]
      end
      mapping = TransformMap.create!(name: "Copy email", input_file_type: input_type, output_file_type: output_type)
      transformation = mapping.transformations.create!(output_column: target,
                                                       column_transformer: FactoryBot.create(:column_transformer),
                                                       input_json: { name: "email" })

      expect do
        patch path, params: { remove_ids: [unused.id, column.id], add: [{ name: "city", position: 2 }] }, as: :json
      end.not_to change { [Column.count, Validation.count] }

      expect(response).to have_http_status(422)
      expect(response.parsed_body).to eq(
        "errors" => { "remove_ids[1].base" => ["cannot delete a column used by a transformation"] },
      )
      expect(Column.exists?(unused.id)).to be true
      expect(Column.exists?(column.id)).to be true
      expect(Validation.exists?(rule.id)).to be true
      expect(Transformation.exists?(transformation.id)).to be true
    end
  end

  {
    "non-array additions" => { add: {} },
    "non-object additions" => { add: ["invalid"] },
    "non-array removal IDs" => { remove_ids: {} },
    "non-integer removal IDs" => { remove_ids: [{ id: 1 }] },
    "nonpositive removal IDs" => { remove_ids: [0] },
  }.each do |description, payload|
    it "returns JSON status 400 for #{description}" do
      rule = column.validations.create!(column_validator: catalog)

      expect do
        patch path, params: { remove_ids: [column.id] }.merge(payload), as: :json
      end.not_to change { [Column.count, Validation.count] }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("error" => a_kind_of(String))
      expect(Column.exists?(column.id)).to be true
      expect(Validation.exists?(rule.id)).to be true
    end
  end

  it "rejects duplicate removal IDs before deleting any columns" do
    rule = column.validations.create!(column_validator: catalog)

    patch path, params: { remove_ids: [column.id, column.id] }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "remove_ids must not contain duplicate IDs")
    expect(Column.exists?(column.id)).to be true
    expect(Validation.exists?(rule.id)).to be true
  end
end
