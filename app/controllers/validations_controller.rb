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

  # PATCH /file_types/:file_type_id/validations
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

    validations = Validation.joins(:column).where(columns: { file_type_id: file_type.id })
    error_prefix = ""
    Validation.transaction do
      removal_ids.each_with_index do |id, index|
        error_prefix = "remove_ids[#{index}]."
        validations.find(id).destroy!
      end

      additions.each_with_index do |payload, index|
        error_prefix = "add[#{index}]."
        attributes = resource_params(payload)
        column = file_type.columns.find(attributes.require(:column_id))
        column.validations.create!(attributes.except(:column_id))
      end
    end

    render json: validations.order(:id), only: FIELDS
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
    errors = error.record.errors.to_hash.transform_keys { |field| "#{error_prefix}#{field}" }
    render json: { errors: errors }, status: 422
  end

  private

  def bulk_model
    Validation
  end

  def resource_params(payload = params.require(:validation))
    rule_parameters(payload, :column_id, :column_validator_id)
  end
end
