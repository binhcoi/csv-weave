require "rails_helper"
require "json"
require "stringio"

RSpec.describe "Validation runs", type: :request do
  include ActiveJob::TestHelper

  let(:file_type) { FileType.create!(name: "Customers") }
  let(:data_file) do
    DataFile.create!(file_type: file_type, file: {
      io: StringIO.new("name\nAda\n\"\"\n"), filename: "customers.csv", content_type: "text/csv", identify: false,
    })
  end

  before do
    file_type.columns.create!(name: "name", position: 0).validations.create!(
      column_validator: ColumnValidator.create!(processor_class: "RequiredValidator", description: "Required"),
    )
  end

  after do
    DataFile.find_each { |record| record.file.purge }
    ValidationRun.find_each { |record| record.error_report.purge }
  end

  def expect_queued_run(response)
    expect(response).to have_http_status(:accepted)
    body = response.parsed_body
    run = ValidationRun.find(body.fetch("id"))
    expect(response.location).to eq("http://www.example.com/validation_runs/#{run.id}")
    expect(body).to include("data_file_id" => data_file.id, "file_type_id" => file_type.id, "status" => "queued",
                            "accepted_rows" => nil, "error_report_url" => nil)
    run
  end

  describe "starting a run" do
    it "starts from POST /data_files/:id/validate" do
      expect { post "/data_files/#{data_file.id}/validate" }.to have_enqueued_job(ValidationRunJob)

      expect_queued_run(response)
    end

    it "starts from POST /validation_runs with a data file ID" do
      expect do
        post "/validation_runs", params: { validation_run: { data_file_id: data_file.id } }, as: :json
      end.to have_enqueued_job(ValidationRunJob)

      expect_queued_run(response)
    end

    it "ignores a client-supplied file type and status" do
      other = FileType.create!(name: "Other")
      post "/validation_runs", params: { validation_run: { data_file_id: data_file.id, file_type_id: other.id,
                                                           status: "succeeded" } }, as: :json

      expect_queued_run(response)
    end

    it "returns 404 for an unknown data file in the path" do
      expect { post "/data_files/999999/validate" }.not_to change(ValidationRun, :count)

      expect(response).to have_http_status(:not_found)
      expect(enqueued_jobs).to be_empty
    end

    it "returns 422 for an unknown data file in the body" do
      expect do
        post "/validation_runs", params: { validation_run: { data_file_id: 999_999 } }, as: :json
      end.not_to change(ValidationRun, :count)

      expect(response).to have_http_status(422)
      expect(response.parsed_body).to eq("errors" => { "data_file" => ["must exist"] })
    end

    it "returns 400 for a missing wrapper, missing ID, or malformed ID" do
      [{}, { validation_run: {} }, { validation_run: { data_file_id: "abc" } }, { validation_run: "x" }].each do |params|
        post "/validation_runs", params: params, as: :json
        expect(response).to have_http_status(:bad_request), "expected 400 for #{params.inspect}"
        expect(response.parsed_body).to have_key("error")
      end
    end
  end

  describe "reusing runs" do
    it "returns the existing run with 200 instead of starting a duplicate, from either endpoint" do
      post "/data_files/#{data_file.id}/validate"
      first = expect_queued_run(response)

      expect { post "/data_files/#{data_file.id}/validate" }.not_to have_enqueued_job
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("id")).to eq(first.id)

      perform_enqueued_jobs
      post "/validation_runs", params: { validation_run: { data_file_id: data_file.id } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => first.id, "status" => "succeeded")
      expect(ValidationRun.count).to eq(1)
    end

    it "starts a new run after the file type's validations change" do
      post "/data_files/#{data_file.id}/validate"
      first_id = response.parsed_body.fetch("id")
      perform_enqueued_jobs
      file_type.columns.sole.validations.sole.destroy!

      post "/data_files/#{data_file.id}/validate"

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body.fetch("id")).not_to eq(first_id)
    end
  end

  describe "reading a run and its error report" do
    it "returns 409 for the report until the run finishes, then reports status and redirects to the file" do
      post "/data_files/#{data_file.id}/validate"
      run = ValidationRun.find(response.parsed_body.fetch("id"))

      get "/validation_runs/#{run.id}/error_report"
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => "Validation run is queued")

      perform_enqueued_jobs

      get "/validation_runs/#{run.id}"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("status" => "succeeded", "accepted_rows" => 1, "rejected_rows" => 1, "error_count" => 1,
                              "failure_reason" => nil,
                              "error_report_url" => "http://www.example.com/validation_runs/#{run.id}/error_report")
      expect(body.fetch("finished_at")).to be_present

      get body.fetch("error_report_url")
      expect(response).to have_http_status(:found)
      follow_redirect!
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.headers.fetch("Content-Disposition")).to include("attachment", "validation_run_#{run.id}_errors.jsonl")
      expect(JSON.parse(response.body.lines.sole)).to include("record_number" => 3, "stage" => "input_validation", "column" => "name")
    end

    it "returns 404 for the report of a failed run that has none" do
      run = ValidationRun.create!(data_file: data_file, configuration_digest: "digest")
      run.update!(status: "failed", failure_reason: "unexpected error (IOError)")

      get "/validation_runs/#{run.id}/error_report"
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Validation run has no error report")
    end

    it "returns 404 for an unknown run" do
      get "/validation_runs/999999"
      expect(response).to have_http_status(:not_found)

      get "/validation_runs/999999/error_report"
      expect(response).to have_http_status(:not_found)
    end
  end
end
