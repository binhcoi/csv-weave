require "rails_helper"

RSpec.describe "Configuration request payloads", type: :request do
  {
    "/file_types" => :file_type,
    "/columns" => :column,
    "/transform_maps" => :transform_map,
    "/validations" => :validation,
    "/transformations" => :transformation,
  }.each do |path, key|
    { "string" => "invalid", "array" => [{}] }.each do |type, payload|
      it "returns JSON status 400 for a #{type} instead of an object at #{path}" do
        post path, params: { key => payload }, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include("error" => a_kind_of(String))
      end
    end
  end
end
