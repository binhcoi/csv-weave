module ConfigurationValidation
  class InvalidConfiguration < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors.freeze
      super("Invalid configuration")
    end
  end

  private

  def validate!(records)
    errors = records.flat_map do |record|
      record.valid?
      record.errors.map do |error|
        { resource: record.model_name.singular, id: record.id,
          field: error.attribute.to_s, message: error.message }
      end
    end
    raise InvalidConfiguration.new(errors) if errors.any?
  end

  def validators_for(file_type)
    file_type.columns.flat_map(&:validations).map { |rule| rule.column_validator.get_validator(rule) }
  end
end
