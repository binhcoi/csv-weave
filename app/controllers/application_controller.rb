class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Record not found" }, status: :not_found
  end
  rescue_from ActionController::ParameterMissing, ActionController::BadRequest do |error|
    render json: { error: error.message }, status: :bad_request
  end

  private

  def rule_parameters(payload, *references)
    unless payload.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "Expected an object"
    end

    attributes = payload.permit(*references)
    # input_json is arbitrary JSON, including nil. The catalog schema validates its contents.
    attributes[:input_json] = payload[:input_json].as_json if payload.key?(:input_json)
    attributes
  end
end
