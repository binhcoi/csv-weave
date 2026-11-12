class FileTypeConfigurationLoader
  include ConfigurationValidation

  Configuration = Data.define(:file_type, :columns, :validators)

  def self.load(file_type_id)
    new.load(file_type_id)
  end

  def load(file_type_id)
    file_type = FileType.strict_loading.includes(columns: { validations: :column_validator }).find(file_type_id)
    columns = file_type.columns.to_a
    validations = columns.flat_map(&:validations)

    validate!(validations.map(&:column_validator).uniq)
    validate!([file_type, *columns, *validations])

    Configuration.new(file_type: file_type, columns: columns.freeze, validators: validators_for(file_type).freeze)
  end
end
