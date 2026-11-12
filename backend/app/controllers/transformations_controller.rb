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

  # PATCH /transform_maps/:transform_map_id/transformations
  def bulk_modify
    mapping = TransformMap.find(params[:transform_map_id])
    additions = nested_items(params, :add)
    removal_ids = params.fetch(:remove_ids, [])

    unless removal_ids.is_a?(Array) && removal_ids.all? { |id| id.is_a?(Integer) && id.positive? }
      raise ActionController::BadRequest, "remove_ids must be an array of positive integers"
    end
    unless removal_ids.uniq.size == removal_ids.size
      raise ActionController::BadRequest, "remove_ids must not contain duplicate IDs"
    end

    transformations = mapping.transformations
    error_prefix = ""
    Transformation.transaction do
      removal_ids.each_with_index do |id, index|
        error_prefix = "remove_ids[#{index}]."
        transformations.find(id).destroy!
      end

      additions.each_with_index do |payload, index|
        error_prefix = "add[#{index}]."
        transformations.create!(rule_parameters(payload, :output_column_id, :column_transformer_id))
      end
    end

    render json: transformations.order(:id), only: FIELDS
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
    errors = error.record.errors.to_hash.transform_keys { |field| "#{error_prefix}#{field}" }
    render json: { errors: errors }, status: 422
  end

  private

  def bulk_model
    Transformation
  end

  def resource_params(payload = params.require(:transformation))
    rule_parameters(payload, :transform_map_id, :output_column_id, :column_transformer_id)
  end
end
