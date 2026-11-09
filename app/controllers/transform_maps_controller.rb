class TransformMapsController < ApplicationController
  FIELDS = [:id, :name, :description, :input_file_type_id, :output_file_type_id].freeze
  TRANSFORMATION_FIELDS = [:id, :transform_map_id, :output_column_id, :column_transformer_id, :input_json].freeze

  # GET /transform_maps
  def index
    render json: TransformMap.includes(:transformations).order(:id), only: FIELDS,
           include: { transformations: { only: TRANSFORMATION_FIELDS } }
  end

  # GET /transform_maps/:id
  def show
    render json: TransformMap.find(params[:id]), only: FIELDS,
           include: { transformations: { only: TRANSFORMATION_FIELDS } }
  end

  # POST /transform_maps
  def create
    payload = params.require(:transform_map)
    unless payload.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "Expected an object"
    end

    mapping = TransformMap.new(payload.permit(:name, :description, :input_file_type_id, :output_file_type_id))
    error_prefix = ""

    TransformMap.transaction do
      mapping.save!
      nested_items(payload, :transformations).each_with_index do |transformation_payload, index|
        error_prefix = "transformations[#{index}]."
        mapping.transformations.create!(rule_parameters(transformation_payload, :output_column_id, :column_transformer_id))
      end
    end

    render json: mapping, only: FIELDS, status: :created
  rescue ActiveRecord::RecordInvalid => error
    errors = error.record.errors.to_hash.transform_keys { |field| "#{error_prefix}#{field}" }
    render json: { errors: errors }, status: 422
  end

  # PATCH/PUT /transform_maps/:id
  def update
    mapping = TransformMap.find(params[:id])
    if mapping.update(map_params)
      render json: mapping, only: FIELDS
    else
      render json: { errors: mapping.errors.to_hash }, status: 422
    end
  end

  # DELETE /transform_maps/:id
  def destroy
    transform_map = TransformMap.find(params[:id])
    if transform_map.destroy
      head :no_content
    else
      render json: { errors: transform_map.errors.to_hash }, status: 422
    end
  rescue ActiveRecord::InvalidForeignKey
    # A conversion run was created after the dependency check.
    render json: { errors: { base: ["cannot delete a transform map used by a conversion run"] } }, status: 422
  end

  private

  def map_params
    params.expect(transform_map: [:name, :description, :input_file_type_id, :output_file_type_id])
  end
end
