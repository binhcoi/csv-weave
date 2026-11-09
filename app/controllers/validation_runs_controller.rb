class ValidationRunsController < ApplicationController
  # POST /validation_runs with { validation_run: { data_file_id } }
  def create
    payload = params.require(:validation_run)
    raise ActionController::BadRequest, "Expected an object" unless payload.is_a?(ActionController::Parameters)

    data_file_id = payload.require(:data_file_id)
    unless data_file_id.to_s.match?(/\A[1-9]\d*\z/)
      raise ActionController::BadRequest, "data_file_id must be a positive integer"
    end

    data_file = DataFile.find_by(id: data_file_id)
    unless data_file
      render json: { errors: { data_file: ["must exist"] } }, status: 422
      return
    end

    start(data_file)
  end

  # POST /data_files/:id/validate
  def create_for_data_file
    start(DataFile.find(params[:id]))
  end

  def show
    render json: serialize(ValidationRun.with_attached_error_report.find(params[:id]))
  end

  def error_report
    run = ValidationRun.with_attached_error_report.find(params[:id])
    unless run.finished?
      render json: { error: "Validation run is #{run.status}" }, status: :conflict
      return
    end
    unless run.error_report.attached?
      render json: { error: "Validation run has no error report" }, status: :not_found
      return
    end

    redirect_to rails_storage_redirect_url(run.error_report, disposition: :attachment)
  end

  private

  def start(data_file)
    run, created = ValidationRun.start!(data_file)
    # 202 for a new run; 200 when an existing run for the same file and configuration is reused.
    render json: serialize(run), status: created ? :accepted : :ok, location: validation_run_url(run)
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: error.record.errors.to_hash }, status: 422
  end

  def serialize(run)
    { id: run.id, data_file_id: run.data_file_id, file_type_id: run.file_type_id, status: run.status,
      accepted_rows: run.accepted_rows, rejected_rows: run.rejected_rows, error_count: run.error_count,
      failure_reason: run.failure_reason, started_at: run.started_at, finished_at: run.finished_at,
      created_at: run.created_at, updated_at: run.updated_at,
      error_report_url: (error_report_validation_run_url(run) if run.error_report.attached?) }
  end
end
