require "rails_helper"

RSpec.describe "Read-only processor catalogs", type: :request do
  [[:column_validator, "/column_validators"], [:column_transformer, "/column_transformers"]].each do |factory, path|
    context path do
      it "returns public catalog metadata, including the optional input schema" do
        catalog = FactoryBot.create(factory)

        get path, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([{
          "id" => catalog.id, "processor_class" => catalog.processor_class,
          "description" => catalog.description, "input_schema" => catalog.input_schema,
        }])
      end

      it "exposes only the index route" do
        get "#{path}/1", as: :json
        expect(response).to have_http_status(:not_found)
        post path, params: {}, as: :json
        expect(response).to have_http_status(:not_found)
        patch "#{path}/1", params: {}, as: :json
        expect(response).to have_http_status(:not_found)
        delete "#{path}/1", as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
