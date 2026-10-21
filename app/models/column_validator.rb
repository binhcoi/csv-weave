class ColumnValidator < ApplicationRecord
  PROCESSOR_CLASSES = [
    "RequiredValidator",
  ].freeze

  validates :processor_class, presence: true, inclusion: { in: PROCESSOR_CLASSES }, uniqueness: true

  def get_validator(column, input_json)
    raise "unrecognize validator" unless PROCESSOR_CLASSES.include?(processor_class)
    namespace = "Validators"
    class_name = "#{namespace}::#{processor_class}"
    class_name.constantize().new(column, input_json)
  end
end
