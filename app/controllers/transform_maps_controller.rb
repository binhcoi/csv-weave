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
    mapping = TransformMap.new(map_params)
    if mapping.save
      render json: mapping, only: FIELDS, status: :created
    else
      render json: { errors: mapping.errors.to_hash }, status: 422
    end
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
    TransformMap.find(params[:id]).destroy!
    head :no_content
  end

  private

  def map_params
    params.expect(transform_map: [:name, :description, :input_file_type_id, :output_file_type_id])
  end
end
