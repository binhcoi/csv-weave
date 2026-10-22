class InputJsonValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    catalog = record.public_send(options.fetch(:catalog))
    return unless catalog

    schema = catalog.input_schema
    return if schema.nil?

    unless schema.is_a?(Hash) && JSONSchemer.valid_schema?(schema)
      record.errors.add(attribute, "cannot be validated because the catalog input schema is invalid")
      return
    end

    JSONSchemer.schema(schema).validate(value).each do |error|
      record.errors.add(attribute, error.fetch("error"))
    end
  rescue JSONSchemer::UnknownRef
    record.errors.add(attribute, "cannot be validated because the catalog schema contains an unresolved reference")
  end
end
