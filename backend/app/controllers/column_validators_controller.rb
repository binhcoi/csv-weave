class ColumnValidatorsController < ApplicationController
  # GET /column_validators
  def index
    render json: ColumnValidator.order(:id), only: [:id, :processor_class, :description, :input_schema]
  end
end
