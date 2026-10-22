class TransformationsController < ApplicationController
  include BulkRuleActions

  FIELDS = [:id, :transform_map_id, :output_column_id, :column_transformer_id, :input_json].freeze

  # GET /transformations
  def index
    transformations = Transformation.order(:id)
    if params[:transform_map_id].present?
      transformations = transformations.where(transform_map_id: params[:transform_map_id])
    end
    render json: transformations, only: FIELDS
  end

  # GET /transformations/:id
  def show
    render json: Transformation.find(params[:id]), only: FIELDS
  end

  # POST /transformations
  def create
    transformation = Transformation.new(resource_params)
    if transformation.save
      render json: transformation, only: FIELDS, status: :created
    else
      render json: { errors: transformation.errors.to_hash }, status: 422
    end
  end

  # PATCH/PUT /transformations/:id
  def update
    transformation = Transformation.find(params[:id])
    if transformation.update(resource_params)
      render json: transformation, only: FIELDS
    else
      render json: { errors: transformation.errors.to_hash }, status: 422
    end
  end

  # DELETE /transformations/:id
  def destroy
    Transformation.find(params[:id]).destroy!
    head :no_content
  end

  private

  def bulk_model
    Transformation
  end

  def resource_params(payload = params.require(:transformation))
    rule_parameters(payload, :transform_map_id, :output_column_id, :column_transformer_id)
  end
end
