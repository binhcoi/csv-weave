class DataFile < ApplicationRecord
  MAX_UPLOAD_BYTES = Integer(ENV.fetch("DATA_FILE_MAX_BYTES", 1.gigabyte.to_s), 10)
  raise ArgumentError, "DATA_FILE_MAX_BYTES must be positive" unless MAX_UPLOAD_BYTES.positive?

  belongs_to :file_type
  has_one_attached :file

  validate :file_is_present_and_within_limit
  validate :uploaded_file_cannot_change, on: :update

  private

  def file_is_present_and_within_limit
    unless file.attached?
      errors.add(:file, "must be attached")
      return
    end

    if file.blob.byte_size > MAX_UPLOAD_BYTES
      errors.add(:file, "must be at most #{MAX_UPLOAD_BYTES} bytes")
    end
  end

  def uploaded_file_cannot_change
    if will_save_change_to_file_type_id?
      errors.add(:file_type, "cannot change after upload")
    end
    if attachment_changes.key?("file")
      errors.add(:file, "cannot change after upload")
    end
  end
end
