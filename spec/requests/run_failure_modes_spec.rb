require "rails_helper"
require_relative "../support/conversion_run_context"

RSpec.describe "Run request failure modes", type: :request do
  include ActiveJob::TestHelper
  include_context "conversion run records"

  let(:data_file) { upload("name,amount\nAda,3\n") }

  after { purge_conversion_files }

  it "returns 503 with the failed run when the validation job cannot be enqueued" do
    allow(ValidationRunJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")

    post "/data_files/#{data_file.id}/validate"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include("status" => "failed",
                                            "failure_reason" => "could not enqueue job (ActiveJob::EnqueueError)")
  end

  it "returns 503 with the failed run when the conversion job cannot be enqueued" do
    allow(ConversionRunJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")

    post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include("status" => "failed")
  end

  it "returns 422 when the map is deleted between lookup and run creation" do
    allow(ConversionRun).to receive(:start!).and_wrap_original do |original, data_file, map|
      Transformation.where(transform_map_id: map.id).delete_all
      TransformMap.where(id: map.id).delete_all
      original.call(data_file, map)
    end

    post "/data_files/#{data_file.id}/convert", params: { conversion_run: { transform_map_id: transform_map.id } }, as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body).to eq("errors" => { "transform_map" => ["must exist"] })
  end

  it "returns 422 when a conversion run is created between the delete check and the delete" do
    allow_any_instance_of(TransformMap).to receive(:reject_deletion_if_used_by_conversion_runs) do |map|
      ConversionRun.create!(data_file: data_file, transform_map: map, configuration_digest: "raced")
    end

    delete "/transform_maps/#{transform_map.id}", as: :json

    expect(response).to have_http_status(422)
    expect(response.parsed_body).to eq("errors" => { "base" => ["cannot delete a transform map used by a conversion run"] })
  end
end
