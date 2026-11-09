require "rails_helper"
require "json"
require_relative "../support/conversion_run_context"

RSpec.describe "Conversion runs", type: :request do
  include ActiveJob::TestHelper
  include_context "conversion run records"

  let(:data_file) { upload("name,amount\nAda,3\n,4\n") }

  after { purge_conversion_files }

  def follow_download(url)
    get url
    expect(response).to have_http_status(:found)
    follow_redirect!
    follow_redirect!
    expect(response).to have_http_status(:ok)
    response
  end

  describe "starting a run" do
    it "starts from POST /data_files/:id/convert" do
      expect do
        post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json
      end.to have_enqueued_job(ConversionRunJob)

      expect(response).to have_http_status(:accepted)
      run = ConversionRun.find(response.parsed_body.fetch("id"))
      expect(response.location).to eq("http://www.example.com/conversion_runs/#{run.id}")
      expect(response.parsed_body).to include("data_file_id" => data_file.id, "transform_map_id" => transform_map.id,
                                              "status" => "queued", "output_url" => nil, "error_report_url" => nil)
    end

    it "starts from POST /conversion_runs and reuses the run from either endpoint" do
      post "/conversion_runs", params: { conversion_run: { data_file_id: data_file.id, transform_map_id: transform_map.id } },
                               as: :json
      expect(response).to have_http_status(:accepted)
      first_id = response.parsed_body.fetch("id")

      expect do
        post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json
      end.not_to have_enqueued_job
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("id")).to eq(first_id)
    end

    it "returns 422 with a rejected run when the file type does not match the map, also on repeat" do
      wrong = upload("name,total\nAda,3\n", file_type: output_type)

      2.times do
        expect do
          post "/data_files/#{wrong.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json
        end.not_to have_enqueued_job
        expect(response).to have_http_status(422)
        expect(response.parsed_body).to include("status" => "rejected", "failure_reason" => ConversionRun::FILE_TYPE_MISMATCH)
      end
      expect(ConversionRun.count).to eq(1)
    end

    it "returns 404 for an unknown data file in the path" do
      post "/data_files/999999/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 naming each unknown reference in the body" do
      post "/conversion_runs", params: { conversion_run: { data_file_id: 999_999, transform_map_id: 999_999 } }, as: :json
      expect(response).to have_http_status(422)
      expect(response.parsed_body).to eq("errors" => { "data_file" => ["must exist"], "transform_map" => ["must exist"] })

      post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: 999_999 } }, as: :json
      expect(response).to have_http_status(422)
      expect(response.parsed_body).to eq("errors" => { "transform_map" => ["must exist"] })
      expect(ConversionRun.count).to eq(0)
    end

    it "returns 400 for missing or malformed parameters" do
      [
        ["/conversion_runs", {}],
        ["/conversion_runs", { conversion_run: { transform_map_id: 1 } }],
        ["/conversion_runs", { conversion_run: { data_file_id: 1, transform_map_id: "abc" } }],
        ["/data_files/#{data_file.id}/convert", {}],
        ["/data_files/#{data_file.id}/convert", { conversion_run: "x" }],
      ].each do |path, params|
        post path, params: params, as: :json
        expect(response).to have_http_status(:bad_request), "expected 400 for #{path} #{params.inspect}"
        expect(response.parsed_body).to have_key("error")
      end
    end
  end

  describe "reading a run and downloading results" do
    it "returns 409 until finished, then exposes output and error report downloads" do
      post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json
      run_id = response.parsed_body.fetch("id")

      %w[output error_report].each do |file|
        get "/conversion_runs/#{run_id}/#{file}"
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body).to eq("error" => "Conversion run is queued")
      end

      perform_enqueued_jobs
      get "/conversion_runs/#{run_id}"
      body = response.parsed_body
      expect(body).to include("status" => "succeeded", "accepted_rows" => 1, "rejected_rows" => 1, "error_count" => 1,
                              "output_url" => "http://www.example.com/conversion_runs/#{run_id}/output",
                              "error_report_url" => "http://www.example.com/conversion_runs/#{run_id}/error_report")

      output = follow_download(body.fetch("output_url"))
      expect(output.headers.fetch("Content-Disposition")).to include("attachment", "conversion_run_#{run_id}.csv")
      expect(output.body).to eq("name,total\nAda,3\n")

      report = follow_download(body.fetch("error_report_url"))
      expect(JSON.parse(report.body.lines.sole)).to include("record_number" => 3, "column" => "name")
    end

    it "returns 404 for output of a rejected run and for an unknown run" do
      wrong = upload("name,total\nAda,3\n", file_type: output_type)
      post "/data_files/#{wrong.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json
      run_id = response.parsed_body.fetch("id")

      get "/conversion_runs/#{run_id}/output"
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Conversion run has no output")

      get "/conversion_runs/999999"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "returns 422 when deleting a transform map that has conversion runs" do
    post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json

    delete "/transform_maps/#{transform_map.id}", as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body).to eq("errors" => { "base" => ["cannot delete a transform map used by a conversion run"] })
    expect(TransformMap.exists?(transform_map.id)).to be(true)
  end
end
