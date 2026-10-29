require "csv"
require "json"

class CsvValidationRunner
  Result = Data.define(:accepted_rows, :rejected_rows, :error_count)

  class InvalidFile < StandardError
    attr_reader :error, :result

    def initialize(error, result)
      @error = error.freeze
      @result = result
      super(error.fetch(:reason))
    end
  end

  def initialize(columns:, validators:)
    @input_headers = columns.map(&:name)
    @input_validators = validators
  end

  # Caller owns both IOs and can retain the JSON Lines report on InvalidFile.
  def run(input:, error_output:)
    @accepted_rows = 0
    @rejected_rows = 0
    @error_count = 0
    @record_number = 1
    @error_output = error_output
    @error_output.binmode
    @error_output.set_encoding(Encoding::UTF_8)

    input.binmode
    bom_encoding = input.set_encoding_by_bom
    if bom_encoding && bom_encoding != Encoding::UTF_8
      invalid_file!("encoding", "input must be UTF-8", record_number: nil)
    end
    input.set_encoding(Encoding::UTF_8)
    reader = CSV.new(input)
    headers = reader.shift
    validate_headers!(headers)

    prepare_output

    loop do
      @record_number += 1
      fields = reader.shift
      break if fields.nil?

      process_row(fields, headers)
    end
    finish_output
    @error_output.flush
    result
  rescue CSV::InvalidEncodingError
    # CSV may detect invalid bytes in a buffered chunk before yielding its rows.
    invalid_file!("encoding", "input contains invalid UTF-8", record_number: nil)
  rescue CSV::MalformedCSVError => error
    invalid_file!("parsing", error.message)
  end

  private

  # Conversion extends these hooks after the shared input checks succeed.
  def prepare_output
  end

  def finish_output
  end

  def process_valid_row(_source)
    []
  end

  def validate_headers!(headers)
    invalid_file!("headers", "input must contain a header record") unless headers
    if headers.empty? || headers.any?(&:blank?)
      invalid_file!("headers", "headers must be nonblank")
    end

    duplicates = headers.tally.select { |_name, count| count > 1 }.keys
    if duplicates.any?
      invalid_file!("headers", "duplicate headers: #{duplicates.map(&:inspect).join(', ')}")
    end

    missing = @input_headers - headers
    if missing.any?
      invalid_file!("headers", "missing headers: #{missing.map(&:inspect).join(', ')}")
    end
  end

  def process_row(fields, headers)
    if fields.length != headers.length
      @rejected_rows += 1
      write_error(row_error("row_shape", nil, "CSV", "expected #{headers.length} fields, got #{fields.length}"))
      return
    end

    source = CSV::Row.new(headers, fields)
    failures = validation_errors(@input_validators, source, "input_validation")
    failures = process_valid_row(source) if failures.empty?

    if failures.any?
      @rejected_rows += 1
      failures.each { |error| write_error(error) }
    else
      @accepted_rows += 1
    end
  end

  def validation_errors(processors, row, stage)
    processors.filter_map do |processor|
      next if processor.validate(row)

      row_error(stage, processor.column.name, processor.class.name.demodulize, processor.failure_message)
    end
  end

  def row_error(stage, column, operation, reason)
    { record_number: @record_number, stage: stage, column: column, operation: operation, reason: reason }
  end

  def invalid_file!(stage, reason, record_number: @record_number)
    error = row_error(stage, nil, "CSV", reason).merge(record_number: record_number)
    write_error(error)
    @error_output.flush
    raise InvalidFile.new(error, result)
  end

  def write_error(error)
    @error_output.write("#{JSON.generate(error)}\n")
    @error_count += 1
  end

  def result
    Result.new(accepted_rows: @accepted_rows, rejected_rows: @rejected_rows, error_count: @error_count)
  end
end
