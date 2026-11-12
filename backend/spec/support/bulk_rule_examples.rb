RSpec.shared_examples "atomic rule bulk writes" do |path, collection_key, rule_class|
  let(:bulk_records) { create_rows.map { |attributes| rule_class.create!(attributes) } }
  let(:replacement_input) { { "source_column" => "updated_source" } }

  it "bulk creates rules in request order and returns status 201" do
    rows = create_rows
    expect do
      post "#{path}/bulk", params: { collection_key => rows }, as: :json
    end.to change(rule_class, :count).by(2)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.map { |row| row.except("id") }).to eq(rows.map(&:stringify_keys))
    response.parsed_body.each do |row|
      expect(rule_class.exists?(row.fetch("id"))).to be true
    end
  end

  it "rolls back bulk creation and identifies the failing item when a later rule is invalid" do
    rows = [create_rows.first, invalid_row]
    expect do
      post "#{path}/bulk", params: { collection_key => rows }, as: :json
    end.not_to change(rule_class, :count)

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").first).to include("index" => 1, "errors" => a_kind_of(Hash))
  end

  it "bulk updates existing rules without creating additional records" do
    records = bulk_records
    rows = records.map { |record| { id: record.id, input_json: replacement_input } }
    expect do
      patch "#{path}/bulk", params: { collection_key => rows }, as: :json
    end.not_to change(rule_class, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |row| row.fetch("id") }).to eq(records.map(&:id))
    expect(response.parsed_body.map { |row| row.fetch("input_json") }).to eq([replacement_input, replacement_input])
    expect(records.map { |record| record.reload.input_json }).to eq([replacement_input, replacement_input])
  end

  it "rolls back earlier updates when a later rule is invalid" do
    first, second = bulk_records
    original = first.input_json.deep_dup
    rows = [{ id: first.id, input_json: replacement_input }, invalid_row.merge(id: second.id)]

    patch "#{path}/bulk", params: { collection_key => rows }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body.fetch("errors").first.fetch("index")).to eq(1)
    expect(first.reload.input_json).to eq(original)
    expect(second.reload.attributes.slice(*create_rows.last.keys.map(&:to_s))).to eq(create_rows.last.stringify_keys)
  end

  it "rolls back earlier updates and returns the index of a missing record" do
    first = bulk_records.first
    original = first.input_json.deep_dup

    patch "#{path}/bulk", params: { collection_key => [
      { id: first.id, input_json: replacement_input }, { id: 0, input_json: replacement_input },
    ] }, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("errors" => [{ "index" => 1, "error" => "Record not found" }])
    expect(first.reload.input_json).to eq(original)
  end

  it "rejects duplicate update IDs without keeping earlier changes" do
    first = bulk_records.first
    original = first.input_json.deep_dup

    patch "#{path}/bulk", params: { collection_key => [
      { id: first.id, input_json: replacement_input }, { id: first.id, input_json: replacement_input },
    ] }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(first.reload.input_json).to eq(original)
  end

  it "rolls back earlier updates when a later item lacks an ID" do
    first = bulk_records.first
    original = first.input_json.deep_dup

    patch "#{path}/bulk", params: { collection_key => [
      { id: first.id, input_json: replacement_input }, { input_json: replacement_input },
    ] }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(first.reload.input_json).to eq(original)
  end

  { "empty array" => [], "object" => { id: 1 }, "non-object item" => ["invalid"] }.each do |name, payload|
    it "rejects a bulk #{name} payload with status 400" do
      expect do
        post "#{path}/bulk", params: { collection_key => payload }, as: :json
      end.not_to change(rule_class, :count)

      expect(response).to have_http_status(:bad_request)
    end
  end
end
