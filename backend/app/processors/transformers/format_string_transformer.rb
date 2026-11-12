module Transformers
  class FormatStringTransformer < BaseTransformer
    TOKEN = /%%|%\{[^{}]+\}|%/

    # input_json = {
    #   "source_columns" => ["given_name", "family_name"],
    #   "format" => "%{family_name}, %{given_name}"
    # }
    def transform(source, destination)
      values = source_columns.transform_values { |column| column.get_data(source).to_s }
      destination[output_column_name] = render(values)
      nil
    rescue ArgumentError => error
      destination[output_column_name] = nil
      error.message
    end

    def source_column_names
      return [] unless input_json.is_a?(Hash)

      names = input_json["source_columns"]
      names.is_a?(Array) ? names : []
    end

    def validate_configuration
      render(source_columns.transform_values { "" })
    rescue ArgumentError => error
      @transformation.errors.add(:input_json, error.message)
    end

    def renamed_source_configuration(old_name, new_name)
      template = input_json.fetch("format").gsub(TOKEN) do |token|
        token == "%{#{old_name}}" ? "%{#{new_name}}" : token
      end
      super.merge("format" => template)
    end

    private

    def source_columns
      names = source_column_names
      unless names.any? && names.all? { |name| name.is_a?(String) && !name.empty? }
        raise ArgumentError, "source_columns must be a nonempty array of nonempty strings"
      end

      columns = input_columns.index_by(&:name)
      names.uniq.to_h do |name|
        column = columns.fetch(name) do
          raise ArgumentError, "source column #{name.inspect} does not exist in the map's input file type"
        end
        [name, column]
      end
    end

    def render(values)
      template = input_json["format"]
      raise ArgumentError, "format must be a string" unless template.is_a?(String)

      template.gsub(TOKEN) do |token|
        case token
        when "%%"
          "%"
        when "%"
          raise ArgumentError, "format supports only %{column_name} placeholders and %% escapes"
        else
          name = token[2...-1]
          values.fetch(name) do
            raise ArgumentError, "format placeholder #{name.inspect} must name a listed source column"
          end
        end
      end
    end
  end
end
