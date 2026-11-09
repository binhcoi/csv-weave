class ValidationRunJob < ProcessingRunJob
  private

  def execute(run)
    configuration = FileTypeConfigurationLoader.load(run.file_type_id)
    if FileTypeConfigurationDigest.for(run.file_type_id) != run.configuration_digest
      return finish(run, :failed, failure_reason: "configuration changed after the run was requested")
    end

    report = tempfile("validation-run-#{run.id}-", ".jsonl")
    report_attachment = { error_report: [report, "validation_run_#{run.id}_errors.jsonl", "application/x-ndjson"] }
    runner = CsvValidationRunner.new(columns: configuration.columns, validators: configuration.validators)
    begin
      result = run.data_file.file.open { |input| runner.run(input: input, error_output: report) }
      finish(run, :succeeded, result: result, attachments: report_attachment)
    rescue CsvValidationRunner::InvalidFile => error
      finish(run, :rejected, result: error.result, attachments: report_attachment, failure_reason: error.message)
    end
  end
end
