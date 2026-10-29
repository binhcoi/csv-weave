require "bigdecimal"

class CsvConversionRunner < CsvValidationRunner
  def initialize(configuration)
    super(columns: configuration.input_columns, validators: configuration.input_validators)
    @configuration = configuration
    @output_headers = configuration.output_columns.map(&:name)
  end

  # Discard partial CSV on InvalidFile; the shared runner flushes the error report.
  def run(input:, output:, error_output:)
    @output = output
    super(input: input, error_output: error_output)
  end

  private

  def prepare_output
    @output.binmode
    @output.set_encoding(Encoding::UTF_8)
    @writer = CSV.new(@output, row_sep: "\n")
    @writer << @output_headers
  end

  def finish_output
    @writer.flush
  end

  def process_valid_row(source)
    destination = CSV::Row.new(@output_headers, Array.new(@output_headers.length))
    failures = @configuration.transformers.filter_map do |processor|
      reason = processor.transform(source, destination)
      row_error("transformation", processor.output_column_name, processor.class.name.demodulize, reason) if reason
    end
    if failures.empty?
      failures = validation_errors(@configuration.output_validators, destination, "output_validation")
    end
    if failures.empty?
      @writer << destination.fields.map { |value| value.is_a?(BigDecimal) ? value.to_s("F") : value }
    end
    failures
  end
end
