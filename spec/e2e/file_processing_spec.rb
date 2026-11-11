require "rails_helper"
require "csv"
require Rails.root.join("e2e/support/configuration_seeder")

# Drives the e2e fixture CSVs through the real API: upload, validate, convert, check status, and
# download outputs, comparing them with e2e/fixtures/expected. Postman runs the same flow manually.
RSpec.describe "End-to-end file processing", type: :request do
  include ActiveJob::TestHelper

  let(:fixtures) { Rails.root.join("e2e/fixtures/basic") }
  let(:configuration) do
    Rails.application.load_seed
    E2e::ConfigurationSeeder.seed!(:basic)
  end

  after do
    DataFile.find_each { |record| record.file.purge }
    ValidationRun.find_each { |record| record.error_report.purge }
    ConversionRun.find_each do |record|
      record.error_report.purge
      record.output.purge
    end
  end

  def upload(name, content: nil, file_type: nil)
    file_type ||= configuration.input_file_type
    file = if content
             Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", true, original_filename: name)
    else
             Rack::Test::UploadedFile.new(fixtures.join(name).to_s, "text/csv")
    end
    post "/data_files", params: { data_file: { file_type_id: file_type.id, file: file } }
    expect(response).to have_http_status(:created)
    response.parsed_body.fetch("id")
  end

  def start_and_perform(path, params = {})
    post path, params: params, as: params.empty? ? nil : :json
    expect(response).to have_http_status(:accepted)
    run_url = response.headers.fetch("Location")
    perform_enqueued_jobs
    get run_url
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  def download(url)
    get url
    expect(response).to have_http_status(:found)
    follow_redirect!
    follow_redirect!
    expect(response).to have_http_status(:ok)
    response.body
  end

  def expected(name)
    File.read(fixtures.join("expected", name))
  end

  it "validates and converts a fully valid file" do
    data_file_id = upload("e2e_test_orders_valid.csv")

    run = start_and_perform("/data_files/#{data_file_id}/validate")
    expect(run).to include("status" => "succeeded", "accepted_rows" => 5, "rejected_rows" => 0, "error_count" => 0)
    expect(download(run.fetch("error_report_url"))).to eq("")

    run = start_and_perform("/data_files/#{data_file_id}/convert",
                            { conversion_run: { transform_map_id: configuration.transform_map.id } })
    expect(run).to include("status" => "succeeded", "accepted_rows" => 5, "rejected_rows" => 0, "error_count" => 0)
    expect(download(run.fetch("output_url"))).to eq(expected("orders_valid_converted.csv"))
    expect(download(run.fetch("error_report_url"))).to eq("")
  end

  it "converts a mixed file, reporting one rejection per stage and keeping the valid rows" do
    data_file_id = upload("e2e_test_orders_mixed.csv")

    run = start_and_perform("/data_files/#{data_file_id}/validate")
    expect(run).to include("status" => "succeeded", "accepted_rows" => 4, "rejected_rows" => 4, "error_count" => 4)
    expect(download(run.fetch("error_report_url"))).to eq(expected("orders_mixed_validation_errors.jsonl"))

    run = start_and_perform("/data_files/#{data_file_id}/convert",
                            { conversion_run: { transform_map_id: configuration.transform_map.id } })
    expect(run).to include("status" => "succeeded", "accepted_rows" => 2, "rejected_rows" => 6, "error_count" => 7)
    expect(download(run.fetch("output_url"))).to eq(expected("orders_mixed_converted.csv"))
    expect(download(run.fetch("error_report_url"))).to eq(expected("orders_mixed_conversion_errors.jsonl"))
  end

  it "rejects a file with a missing header and keeps the error report without an output" do
    data_file_id = upload("e2e_test_orders_bad_header.csv")

    run = start_and_perform("/data_files/#{data_file_id}/convert",
                            { conversion_run: { transform_map_id: configuration.transform_map.id } })
    expect(run).to include("status" => "rejected", "failure_reason" => 'missing headers: "unit_price"', "output_url" => nil)
    expect(download(run.fetch("error_report_url"))).to eq(expected("orders_bad_header_conversion_errors.jsonl"))
  end

  it "rejects a non-UTF-8 file" do
    data_file_id = upload("e2e_test_orders_latin1.csv")

    run = start_and_perform("/data_files/#{data_file_id}/validate")
    expect(run).to include("status" => "rejected", "failure_reason" => "input contains invalid UTF-8")
    expect(download(run.fetch("error_report_url"))).to eq(expected("orders_latin1_validation_errors.jsonl"))
  end

  it "reuses a finished run for the same file and configuration" do
    data_file_id = upload("e2e_test_orders_valid.csv")
    first = start_and_perform("/data_files/#{data_file_id}/validate")

    expect { post "/data_files/#{data_file_id}/validate" }.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("id" => first.fetch("id"), "status" => "succeeded")
  end

  it "fails a run when the configuration changes between the request and its execution" do
    data_file_id = upload("e2e_test_orders_valid.csv")
    post "/data_files/#{data_file_id}/validate"
    expect(response).to have_http_status(:accepted)
    run_url = response.headers.fetch("Location")

    column = configuration.input_file_type.columns.find_by!(name: "qty")
    column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "RequiredValidator"))
    perform_enqueued_jobs

    get run_url
    expect(response.parsed_body).to include("status" => "failed",
                                            "failure_reason" => "configuration changed after the run was requested")
  end

  describe "comprehensive scenario" do
    let(:comprehensive) do
      Rails.application.load_seed
      E2e::ConfigurationSeeder.seed!(:comprehensive)
    end
    let(:fixtures) { Rails.root.join("e2e/fixtures/comprehensive") }

    it "validates and converts registrations using every cataloged operation" do
      data_file_id = upload("e2e_test_registrations_valid.csv", file_type: comprehensive.input_file_type)

      run = start_and_perform("/data_files/#{data_file_id}/validate")
      expect(run).to include("status" => "succeeded", "accepted_rows" => 4, "rejected_rows" => 0, "error_count" => 0)

      run = start_and_perform("/data_files/#{data_file_id}/convert",
                              { conversion_run: { transform_map_id: comprehensive.transform_map.id } })
      expect(run).to include("status" => "succeeded", "accepted_rows" => 4, "rejected_rows" => 0, "error_count" => 0)
      expect(download(run.fetch("output_url"))).to eq(expected("registrations_valid_converted.csv"))
    end

    it "reports a failure for every rule across all three stages for the mixed registrations" do
      data_file_id = upload("e2e_test_registrations_mixed.csv", file_type: comprehensive.input_file_type)

      run = start_and_perform("/data_files/#{data_file_id}/validate")
      expect(run).to include("status" => "succeeded", "accepted_rows" => 8, "rejected_rows" => 9, "error_count" => 13)
      expect(download(run.fetch("error_report_url"))).to eq(expected("registrations_mixed_validation_errors.jsonl"))

      run = start_and_perform("/data_files/#{data_file_id}/convert",
                              { conversion_run: { transform_map_id: comprehensive.transform_map.id } })
      expect(run).to include("status" => "succeeded", "accepted_rows" => 2, "rejected_rows" => 15, "error_count" => 24)
      expect(download(run.fetch("output_url"))).to eq(expected("registrations_mixed_converted.csv"))
      expect(download(run.fetch("error_report_url"))).to eq(expected("registrations_mixed_conversion_errors.jsonl"))
    end
  end

  it "converts a large file", :slow do
    rows = Array.new(3000) do |index|
      "TEST-#{5000 + index},Testa,Fakeworth,12 Apr 2026,SKU-T#{format('%03d', index % 1000)},#{index % 9 + 1},1.25\n"
    end
    content = "order_ref,first,last,ordered_on,product_code,qty,unit_price\n#{rows.join}"
    data_file_id = upload("e2e_test_orders_large.csv", content: content)

    run = start_and_perform("/data_files/#{data_file_id}/convert",
                            { conversion_run: { transform_map_id: configuration.transform_map.id } })
    expect(run).to include("status" => "succeeded", "accepted_rows" => 3000, "rejected_rows" => 0)
    expect(CSV.parse(download(run.fetch("output_url")), headers: true).count).to eq(3000)
  end
end
