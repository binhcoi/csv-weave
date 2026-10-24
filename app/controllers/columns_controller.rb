class ColumnsController < ApplicationController
  FIELDS = [:id, :file_type_id, :name, :description, :position].freeze

  # GET /columns
  def index
    columns = Column.order(:file_type_id, :position, :id)
    columns = columns.where(file_type_id: params[:file_type_id]) if params[:file_type_id].present?
    render json: columns, only: FIELDS
  end

  # GET /columns/:id
  def show
    render json: Column.find(params[:id]), only: FIELDS
  end

  # POST /columns
  def create
    column = Column.new(column_params)
    if column.save
      render json: column, only: FIELDS, status: :created
    else
      render json: { errors: column.errors.to_hash }, status: 422
    end
  end

  # PATCH/PUT /columns/:id
  def update
    column = Column.find(params[:id])
    if column.update(column_params)
      render json: column, only: FIELDS
    else
      render json: { errors: column.errors.to_hash }, status: 422
    end
  end

  # DELETE /columns/:id
  def destroy
    column = Column.find(params[:id])
    if column.destroy
      head :no_content
    else
      render json: { errors: column.errors.to_hash }, status: 422
    end
  end

  # PATCH /file_types/:file_type_id/columns
  def bulk_modify
    file_type = FileType.find(params[:file_type_id])
    additions = params.fetch(:add, [])
    removal_ids = params.fetch(:remove_ids, [])

    unless additions.is_a?(Array) && additions.all? { |item| item.is_a?(ActionController::Parameters) }
      raise ActionController::BadRequest, "add must be an array of objects"
    end
    unless removal_ids.is_a?(Array) && removal_ids.all? { |id| id.is_a?(Integer) && id.positive? }
      raise ActionController::BadRequest, "remove_ids must be an array of positive integers"
    end
    unless removal_ids.uniq.size == removal_ids.size
      raise ActionController::BadRequest, "remove_ids must not contain duplicate IDs"
    end

    error_prefix = ""
    Column.transaction do
      removal_ids.each_with_index do |id, index|
        error_prefix = "remove_ids[#{index}]."
        file_type.columns.find(id).destroy!
      end

      additions.each_with_index do |payload, index|
        error_prefix = "add[#{index}]."
        file_type.columns.create!(payload.permit(:name, :description, :position))
      end
    end

    render json: file_type.columns.reload, only: FIELDS
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
    errors = error.record.errors.to_hash.transform_keys { |field| "#{error_prefix}#{field}" }
    render json: { errors: errors }, status: 422
  end

  private

  def column_params
    params.expect(column: [:file_type_id, :name, :description, :position])
  end
end
