require "rails_helper"
require_relative "../support/bulk_rule_examples"

RSpec.describe "Validations", type: :request do
  let(:file_type) { FileType.create!(name: "Customer import") }
  let(:column) { file_type.columns.create!(name: "email", position: 0) }
  let(:other_column) { file_type.columns.create!(name: "customer_id", position: 1) }
  let(:catalog) { FactoryBot.create(:column_validator) }
  let(:create_rows) do
    [column, other_column].map do |target|
      { column_id: target.id, column_validator_id: catalog.id, input_json: nil }
    end
  end
  let(:invalid_row) { create_rows.last.merge(column_id: nil) }
  let(:validation) { Validation.create!(create_rows.first) }

  it "creates a rule with nullable parameters and only permitted fields" do
    expect do
      post "/validations", params: { validation: create_rows.first.merge(id: -1) }, as: :json
    end.to change(Validation, :count).by(1)

    expect(response).to have_http_status(:created)
    saved = Validation.find(response.parsed_body.fetch("id"))
    expect(saved.id).not_to eq(-1)
    expect(response.parsed_body).to eq(
      "id" => saved.id, "column_id" => column.id, "column_validator_id" => catalog.id, "input_json" => nil,
    )
    expect(saved.input_json).to be_nil
  end

  it "returns field errors with status 422 for an invalid rule" do
    expect do
      post "/validations", params: { validation: invalid_row }, as: :json
    end.not_to change(Validation, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("column")
  end

  it "lists rules for the requested column without including other columns' rules" do
    validation
    Validation.create!(create_rows.last)

    get "/validations", params: { column_id: column.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([{
      "id" => validation.id, "column_id" => column.id, "column_validator_id" => catalog.id, "input_json" => nil,
    }])
  end

  it "returns the requested rule" do
    get "/validations/#{validation.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "id" => validation.id, "column_id" => column.id, "column_validator_id" => catalog.id, "input_json" => nil,
    )
  end

  it "updates permitted references and preserves nested JSON parameters" do
    parameters = { "options" => { "enabled" => true, "values" => [1, { "label" => "example" }] } }
    patch "/validations/#{validation.id}", params: { validation: {
      column_id: other_column.id, input_json: parameters, id: -1,
    } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(validation.reload.column_id).to eq(other_column.id)
    expect(validation.input_json).to eq(parameters)
    expect(response.parsed_body.fetch("id")).to eq(validation.id)
  end

  it "returns errors without persisting an invalid update" do
    patch "/validations/#{validation.id}", params: { validation: { column_id: nil } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors")).to have_key("column")
    expect(validation.reload.column_id).to eq(column.id)
  end

  it "deletes the rule while retaining its column and catalog entry" do
    validation
    expect do
      delete "/validations/#{validation.id}", as: :json
    end.to change(Validation, :count).by(-1)

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
    expect(Column.exists?(column.id)).to be true
    expect(ColumnValidator.exists?(catalog.id)).to be true
  end

  [:get, :patch, :delete].each do |verb|
    it "returns a JSON 404 when #{verb} targets a missing rule" do
      public_send(verb, "/validations/0", params: { validation: { input_json: nil } })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Record not found")
    end
  end

  include_examples "atomic rule bulk writes", "/validations", :validations, Validation

  it "preserves explicit NULL JSON values in bulk updates when the catalog has no schema" do
    rows = bulk_records.map { |record| { id: record.id, input_json: nil } }

    patch "/validations/bulk", params: { validations: rows }, as: :json

    expect(response).to have_http_status(:ok)
    expect(bulk_records.map { |record| record.reload.input_json }).to eq([nil, nil])
  end
end
