class ColumnValidator < ApplicationRecord
  PROCESSOR_CLASSES = [
    "RequiredValidator",
  ].freeze

  has_many :validations
  validates :processor_class, presence: true, inclusion: { in: PROCESSOR_CLASSES }, uniqueness: true
  validates :input_schema, json_schema: true

  def get_validator(column, input_json)
    unless PROCESSOR_CLASSES.include?(processor_class)
      raise ArgumentError, "Unrecognized validator: #{processor_class.inspect}"
    end

    namespace = "Validators"
    class_name = "#{namespace}::#{processor_class}"
    class_name.constantize.new(column, input_json)
  end
end
