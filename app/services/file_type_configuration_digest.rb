require "digest"
require "json"

# Fingerprint of everything that affects validating a file against a file type:
# its columns, their validation rules, and the validator catalog entries they use.
# The file type's name and description are excluded because they do not change results.
class FileTypeConfigurationDigest
  def self.for(file_type_id)
    columns = Column.where(file_type_id: file_type_id).order(:id).pluck(:id, :name, :position)
    validations = Validation.joins(:column).where(columns: { file_type_id: file_type_id })
                            .order(:id).pluck(:id, :column_id, :column_validator_id, :input_json)
    validators = ColumnValidator.where(id: validations.map { |row| row[2] }.uniq)
                                .order(:id).pluck(:id, :processor_class, :input_schema)

    Digest::SHA256.hexdigest(JSON.generate([columns, validations, validators]))
  end
end
