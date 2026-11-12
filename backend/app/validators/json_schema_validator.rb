class JsonSchemaValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.nil?

    unless value.is_a?(Hash) && JSONSchemer.valid_schema?(value)
      record.errors.add(attribute, "must be a valid JSON Schema object")
    end
  rescue JSONSchemer::UnknownRef
    record.errors.add(attribute, "contains an unresolved schema reference")
  end
end
