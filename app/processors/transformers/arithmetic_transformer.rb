require "bigdecimal"

module Transformers
  class ArithmeticTransformer < BaseTransformer
    OPERATORS = ["+", "-", "*", "/"].freeze
    MAX_SCALE = 100

    # input_json = {
    #   "source_columns": ["total", "quantity"],
    #   "operator": "/",
    #   "scale": 2
    # }
    # scale applies to division only.
    def transform(source, destination)
      validate_settings!
      left, right = source_columns.map { |column| operand(column, source) }
      result = BigDecimal.save_limit do
        BigDecimal.limit(0)
        calculate(left, right)
      end
      raise ArgumentError, "arithmetic result must be finite" unless result.finite?

      destination[output_column_name] = result
      nil
    rescue ArgumentError, FloatDomainError, ZeroDivisionError => error
      destination[output_column_name] = nil
      error.message
    end

    def source_column_names
      return [] unless input_json.is_a?(Hash)

      names = input_json["source_columns"]
      names.is_a?(Array) ? names : []
    end

    def validate_configuration
      validate_settings!
      source_columns
    rescue ArgumentError => error
      @transformation.errors.add(:input_json, error.message)
    end

    private

    def validate_settings!
      operator = input_json["operator"] if input_json.is_a?(Hash)
      raise ArgumentError, "operator must be one of +, -, *, /" unless OPERATORS.include?(operator)

      if operator == "/"
        scale = input_json["scale"]
        unless scale.is_a?(Integer) && scale.between?(0, MAX_SCALE)
          raise ArgumentError, "division scale must be an integer from 0 to #{MAX_SCALE}"
        end
      elsif input_json.key?("scale")
        raise ArgumentError, "scale is only supported for division"
      end
    end

    def source_columns
      names = source_column_names
      unless names.size == 2 && names.all? { |name| name.is_a?(String) && !name.empty? }
        raise ArgumentError, "source_columns must contain exactly two nonempty column-name strings"
      end

      columns = input_columns.index_by(&:name)
      names.map do |name|
        columns.fetch(name) do
          raise ArgumentError, "source column #{name.inspect} does not exist in the map's input file type"
        end
      end
    end

    def operand(column, source)
      value = BigDecimal((column.get_data(source).presence || 0).to_s, exception: false)
      return value if value&.finite?

      raise ArgumentError, "source column #{column.name.inspect} contains an invalid finite number"
    end

    def calculate(left, right)
      case input_json.fetch("operator")
      when "+" then left + right
      when "-" then left - right
      when "*" then left * right
      when "/"
        raise ZeroDivisionError, "cannot divide by zero" if right.zero?

        scale = input_json.fetch("scale")
        rounded = (left.to_r / right.to_r * 10**scale).round(half: :up)
        BigDecimal("#{rounded}e-#{scale}")
      end
    end
  end
end
