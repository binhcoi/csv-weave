module BulkRuleActions
  # POST /validations/bulk or /transformations/bulk
  def bulk_create
    write_bulk(updating: false)
  end

  # PATCH /validations/bulk or /transformations/bulk
  def bulk_update
    write_bulk(updating: true)
  end

  private

  # Including controllers supply bulk_model, resource_params(payload), and FIELDS.
  def write_bulk(updating:)
    items = params.require(bulk_model.model_name.route_key)
    unless items.is_a?(Array) && items.all? { |item| item.is_a?(ActionController::Parameters) }
      raise ActionController::BadRequest, "Expected a nonempty array of objects"
    end

    current_index = nil
    seen_ids = {}
    records = bulk_model.transaction do
      items.each_with_index.map do |payload, index|
        current_index = index
        record = updating ? bulk_model.find(payload.permit(:id).require(:id)) : bulk_model.new
        if updating && seen_ids[record.id]
          raise ActionController::BadRequest, "Duplicate id at index #{index}"
        end
        seen_ids[record.id] = true if updating
        record.assign_attributes(resource_params(payload))
        record.save!
        record
      end
    end

    render json: records, only: self.class::FIELDS, status: updating ? :ok : :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: [{ index: current_index, errors: error.record.errors.to_hash }] }, status: 422
  rescue ActiveRecord::RecordNotFound
    render json: { errors: [{ index: current_index, error: "Record not found" }] }, status: :not_found
  end
end
