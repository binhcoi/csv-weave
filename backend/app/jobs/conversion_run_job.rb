class ConversionRunJob < ProcessingRunJob
  private

  def execute(run)
    configuration = ConversionConfigurationLoader.load(run.transform_map_id)
    if ConversionConfigurationDigest.for(run.transform_map_id) != run.configuration_digest
      return finish(run, :failed, failure_reason: "configuration changed after the run was requested")
    end

    report = tempfile("conversion-run-#{run.id}-", ".jsonl")
    output = tempfile("conversion-run-#{run.id}-", ".csv")
    report_attachment = { error_report: [report, "conversion_run_#{run.id}_errors.jsonl", "application/x-ndjson"] }
    runner = CsvConversionRunner.new(configuration)
    begin
      result = run.data_file.file.open do |input|
        runner.run(input: input, output: output, error_output: report, on_row: heartbeat)
      end
      finish(run, :succeeded, result: result,
                              attachments: report_attachment.merge(output: [output, "conversion_run_#{run.id}.csv", "text/csv"]))
    rescue CsvValidationRunner::InvalidFile => error
      # The file is invalid as a whole: keep the error report and discard the partial CSV.
      finish(run, :rejected, result: error.result, attachments: report_attachment, failure_reason: error.message)
    end
  end
end
