module Validators
  class RegexValidator < BaseValidator
    # input_json = {
    #   "pattern" => ""
    # }
    def validate(row)
      data = column.get_data(row)

      return true if !data.present?
      return true if regex.match?(data)

      false
    rescue Regexp::TimeoutError
      false
    end

    def pattern
      input_json.fetch("pattern")
    end

    def failure_message
      "must match the configured pattern within its time limit"
    end

    def regex
      Regexp.new(pattern, timeout: 0.05)
    end

    def validate_configuration
      regex
    rescue RegexpError => error
      @validation.errors.add(
        :input_json,
        "invalid regex pattern: #{error.message}"
      )
    end
  end
end
