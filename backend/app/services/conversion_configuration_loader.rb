class ConversionConfigurationLoader
  include ConfigurationValidation

  Configuration = Data.define(:map, :input_columns, :output_columns,
                              :input_validators, :transformers, :output_validators)

  def self.load(map_id)
    new.load(map_id)
  end

  def load(map_id)
    mapping = TransformMap.strict_loading.includes(
      input_file_type: { columns: { validations: :column_validator } },
      output_file_type: { columns: { validations: :column_validator } },
      transformations: [:column_transformer, :output_column],
    ).find(map_id)

    file_types = [mapping.input_file_type, mapping.output_file_type].uniq
    columns = file_types.flat_map(&:columns)
    validations = columns.flat_map(&:validations)
    transformations = mapping.transformations.to_a
    catalogs = (validations.map(&:column_validator) + transformations.map(&:column_transformer)).uniq

    # Reject invalid catalogs before rule validation can resolve a processor class.
    validate!(catalogs)
    validate!([mapping, *file_types, *columns, *validations, *transformations])

    Configuration.new(
      map: mapping,
      input_columns: mapping.input_file_type.columns.to_a.freeze,
      output_columns: mapping.output_file_type.columns.to_a.freeze,
      input_validators: validators_for(mapping.input_file_type).freeze,
      transformers: transformations.map { |rule| rule.column_transformer.get_transformer(rule) }.freeze,
      output_validators: validators_for(mapping.output_file_type).freeze,
    )
  end
end
