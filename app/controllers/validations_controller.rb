class ValidationsController < ApplicationController
  include BulkRuleActions

  FIELDS = [:id, :column_id, :column_validator_id, :input_json].freeze

  # GET /validations
  def index
    validations = Validation.order(:id)
    validations = validations.where(column_id: params[:column_id]) if params[:column_id].present?
    render json: validations, only: FIELDS
  end

  # GET /validations/:id
  def show
    render json: Validation.find(params[:id]), only: FIELDS
  end

  # POST /validations
  def create
    validation = Validation.new(resource_params)
    if validation.save
      render json: validation, only: FIELDS, status: :created
    else
      render json: { errors: validation.errors.to_hash }, status: 422
    end
  end

  # PATCH/PUT /validations/:id
  def update
    validation = Validation.find(params[:id])
    if validation.update(resource_params)
      render json: validation, only: FIELDS
    else
      render json: { errors: validation.errors.to_hash }, status: 422
    end
  end

  # DELETE /validations/:id
  def destroy
    Validation.find(params[:id]).destroy!
    head :no_content
  end

  private

  def bulk_model
    Validation
  end

  def resource_params(payload = params.require(:validation))
    rule_parameters(payload, :column_id, :column_validator_id)
  end
end
