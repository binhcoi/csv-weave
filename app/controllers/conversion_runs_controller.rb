class ConversionRunsController < ApplicationController
  # POST /conversion_runs with { conversion_run: { data_file_id, transform_map_id } }
  def create
    payload = conversion_payload
    data_file_id = positive_id!(payload, :data_file_id)
    transform_map_id = positive_id!(payload, :transform_map_id)

    start(DataFile.find_by(id: data_file_id), TransformMap.find_by(id: transform_map_id))
  end

  # POST /data_files/:id/convert with { conversion_run: { transform_map_id } }
  def create_for_data_file
    data_file = DataFile.find(params[:id])
    transform_map_id = positive_id!(conversion_payload, :transform_map_id)

    start(data_file, TransformMap.find_by(id: transform_map_id))
  end

  def show
    render json: serialize(ConversionRun.with_attached_output.with_attached_error_report.find(params[:id]))
  end

  def output
    download(:output, "output")
  end

  def error_report
    download(:error_report, "error report")
  end

  private

  def conversion_payload
    payload = params.require(:conversion_run)
    raise ActionController::BadRequest, "Expected an object" unless payload.is_a?(ActionController::Parameters)

    payload
  end

  def positive_id!(payload, key)
    value = payload.require(key)
    raise ActionController::BadRequest, "#{key} must be a positive integer" unless value.to_s.match?(/\A[1-9]\d*\z/)

    value
  end

  def start(data_file, transform_map)
    errors = {}
    errors[:data_file] = ["must exist"] unless data_file
    errors[:transform_map] = ["must exist"] unless transform_map
    return render(json: { errors: errors }, status: 422) if errors.any?

    run, created = ConversionRun.start!(data_file, transform_map)
    # 422 when the file type does not match the map (the rejected run is still returned and reused);
    # otherwise 202 for a new run and 200 when an existing run for the same configuration is reused.
    status = if run.file_type_mismatch? then 422 elsif created then :accepted else :ok end
    render json: serialize(run), status: status, location: conversion_run_url(run)
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: error.record.errors.to_hash }, status: 422
  end

  def download(attachment, label)
    run = ConversionRun.public_send(:"with_attached_#{attachment}").find(params[:id])
    unless run.finished?
      render json: { error: "Conversion run is #{run.status}" }, status: :conflict
      return
    end
    file = run.public_send(attachment)
    unless file.attached?
      render json: { error: "Conversion run has no #{label}" }, status: :not_found
      return
    end

    redirect_to rails_storage_redirect_url(file, disposition: :attachment)
  end

  def serialize(run)
    { id: run.id, data_file_id: run.data_file_id, transform_map_id: run.transform_map_id, status: run.status,
      accepted_rows: run.accepted_rows, rejected_rows: run.rejected_rows, error_count: run.error_count,
      failure_reason: run.failure_reason, started_at: run.started_at, finished_at: run.finished_at,
      created_at: run.created_at, updated_at: run.updated_at,
      output_url: (output_conversion_run_url(run) if run.output.attached?),
      error_report_url: (error_report_conversion_run_url(run) if run.error_report.attached?) }
  end
end
