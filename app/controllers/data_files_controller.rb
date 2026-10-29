class DataFilesController < ApplicationController
  def create
    payload = params.require(:data_file)
    unless payload.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "Expected an object"
    end
    upload = payload.require(:file)
    unless upload.is_a?(ActionDispatch::Http::UploadedFile)
      raise ActionController::BadRequest, "file must be a multipart upload"
    end
    file_type_id = payload.require(:file_type_id)
    unless file_type_id.to_s.match?(/\A[1-9]\d*\z/)
      raise ActionController::BadRequest, "file_type_id must be a positive integer"
    end
    if upload.size > DataFile::MAX_UPLOAD_BYTES
      render json: { error: "file exceeds the #{DataFile::MAX_UPLOAD_BYTES} byte upload limit" }, status: :content_too_large
      return
    end

    data_file = DataFileUpload.create!(file_type_id: file_type_id, upload: upload)
    render json: metadata(data_file), status: :created, location: data_file_url(data_file)
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: error.record.errors.to_hash }, status: 422
  end

  def show
    render json: metadata(DataFile.with_attached_file.find(params[:id]))
  end

  def download
    data_file = DataFile.with_attached_file.find(params[:id])
    redirect_to rails_storage_redirect_url(data_file.file, disposition: :attachment)
  end

  private

  def metadata(data_file)
    blob = data_file.file.blob
    { id: data_file.id, file_type_id: data_file.file_type_id, filename: blob.filename.to_s,
      content_type: blob.content_type, byte_size: blob.byte_size, created_at: data_file.created_at,
      download_url: download_data_file_url(data_file) }
  end
end
