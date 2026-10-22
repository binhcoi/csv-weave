class ColumnTransformer < ApplicationRecord
  PROCESSOR_CLASSES = [
    "CopyTransformer",
  ].freeze

  validates :processor_class, presence: true, inclusion: { in: PROCESSOR_CLASSES }, uniqueness: true
  validates :input_schema, json_schema: true

  def get_transformer(column, input_json)
    unless PROCESSOR_CLASSES.include?(processor_class)
      raise ArgumentError, "Unrecognized transformer: #{processor_class.inspect}"
    end

    namespace = "Transformers"
    class_name = "#{namespace}::#{processor_class}"
    class_name.constantize.new(column, input_json)
  end
end
