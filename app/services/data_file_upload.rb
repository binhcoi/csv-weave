class DataFileUpload
  def self.create!(file_type_id:, upload:)
    record = DataFile.new(file_type_id: file_type_id)
    record.file = { io: upload.tempfile, filename: upload.original_filename, content_type: "text/csv", identify: false }
    record.validate!
    blob = record.file.blob
    upload_started = false

    DataFile.transaction do
      blob.save!
      # Upload before committing the owner. Attaching the blob then avoids a second
      # upload in Active Storage's usual after-commit attachment callback.
      upload_started = true
      blob.upload_without_unfurling(upload.tempfile)
      record.file = blob
      record.save!
    end
    record
  rescue StandardError
    # Database rollback does not remove bytes already written to storage.
    if upload_started && !blob.persisted?
      begin
        blob.delete
      rescue StandardError => cleanup_error
        Rails.logger.error("Failed to clean up upload #{blob.key}: #{cleanup_error.class}")
      end
    end
    raise
  end
end
