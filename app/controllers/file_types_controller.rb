class FileTypesController < ApplicationController
  # POST /file_types
  def create
    payload = params.require(:file_type)
    unless payload.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "Expected an object"
    end

    file_type = FileType.new(payload.permit(:name, :description))
    error_prefix = ""

    FileType.transaction do
      file_type.save!
      nested_items(payload, :columns).each_with_index do |column_payload, column_index|
        error_prefix = "columns[#{column_index}]."
        column = file_type.columns.create!(column_payload.permit(:name, :description, :position))

        nested_items(column_payload, :validations).each_with_index do |validation_payload, validation_index|
          error_prefix = "columns[#{column_index}].validations[#{validation_index}]."
          column.validations.create!(rule_parameters(validation_payload, :column_validator_id))
        end
      end
    end

    render json: file_type, only: [:id, :name, :description], status: :created
  rescue ActiveRecord::RecordInvalid => error
    errors = error.record.errors.to_hash.transform_keys { |field| "#{error_prefix}#{field}" }
    render json: { errors: errors }, status: 422
  end

  # PATCH/PUT /file_types/:id
  def update
    file_type = FileType.find(params[:id])
    if file_type.update(file_type_params)
      render json: file_type, only: [:id, :name, :description]
    else
      render json: { errors: file_type.errors.to_hash }, status: 422
    end
  end

  # GET /file_types
  def index
    file_types = FileType.includes(columns: :validations).order(:id)
    render json: file_types, only: [:id, :name, :description],
           include: {
             columns: {
               only: [:id, :name, :description, :position],
               include: { validations: { only: [:id, :column_validator_id, :input_json] } },
             },
           }
  end

  # GET /file_types/:id
  def show
    file_type = FileType.includes(columns: :validations).find(params[:id])
    render json: file_type, only: [:id, :name, :description],
           include: {
             columns: {
               only: [:id, :name, :description, :position],
               include: { validations: { only: [:id, :column_validator_id, :input_json] } },
             },
           }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "File type not found" }, status: :not_found
  end

  # DELETE /file_types/:id
  def destroy
    file_type = FileType.find(params[:id])
    if file_type.destroy
      head :no_content
    else
      render json: { errors: file_type.errors.to_hash }, status: 422
    end
  end

  private

  def file_type_params
    params.expect(file_type: [:name, :description])
  end
end
