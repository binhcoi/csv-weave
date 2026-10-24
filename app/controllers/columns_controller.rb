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

  private

  def column_params
    params.expect(column: [:file_type_id, :name, :description, :position])
  end
end
