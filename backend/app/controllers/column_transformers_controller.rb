class ColumnTransformersController < ApplicationController
  # GET /column_transformers
  def index
    render json: ColumnTransformer.order(:id), only: [:id, :processor_class, :description, :input_schema]
  end
end
