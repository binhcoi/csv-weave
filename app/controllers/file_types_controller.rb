class FileTypesController < ApplicationController
  # POST /file_types
  def create
    file_type = FileType.new(file_type_params)
    if file_type.save
      render json: file_type,
             only: [:id, :name, :description],
             status: :created
    else
      render json: { errors: file_type.errors.to_hash },
             status: 422
    end
  end

  # GET /file_types
  def index
    file_types = FileType.includes(:columns).order(:id)
    render json: file_types, only: [:id, :name, :description],
           include: {
             columns: {
               only: [:id, :name, :description, :position],
             },
           }
  end

  # GET /file_types/:id
  def show
    file_type = FileType.find(params[:id])
    render json: file_type, only: [:id, :name, :description],
           include: {
             columns: {
               only: [:id, :name, :description, :position],
             },
           }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "File type not found" }, status: :not_found
  end

  private

  def file_type_params
    params.expect(file_type: [:name, :description])
  end
end
