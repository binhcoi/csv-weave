# Creates the E2E-TEST configuration used by end-to-end tests and manual Postman testing:
# an input file type (supplier orders), an output file type (warehouse orders), their validation
# rules, and the transformation map between them. It matches the CSV files in e2e/fixtures.
#
# Seeding is idempotent: if the configuration already exists (found by name) it is returned as-is.
# To reset an edited configuration, clean the E2E-TEST records and seed again.
module E2e
  class ConfigurationSeeder
    NAME_PREFIX = "E2E-TEST".freeze
    INPUT_NAME = "#{NAME_PREFIX} Supplier orders".freeze
    OUTPUT_NAME = "#{NAME_PREFIX} Warehouse orders".freeze
    MAP_NAME = "#{NAME_PREFIX} Supplier to warehouse".freeze

    INPUT_COLUMNS = %w[order_ref first last ordered_on product_code qty unit_price].freeze
    OUTPUT_COLUMNS = %w[order_id customer_name order_date sku quantity line_total].freeze

    # column => [[validator class, input_json], ...]
    INPUT_VALIDATIONS = {
      "order_ref" => [["RequiredValidator", nil]],
      "ordered_on" => [["DateValidator", { "format" => "%d %b %Y" }]],
      "product_code" => [["RegexValidator", { "pattern" => "\\ASKU-" }]],
    }.freeze
    OUTPUT_VALIDATIONS = {
      "quantity" => [["NumericRangeValidator", { "min" => 1 }]],
      "line_total" => [["NumericRangeValidator", { "min" => 0 }]],
    }.freeze

    # output column => [transformer class, input_json]
    TRANSFORMATIONS = {
      "order_id" => ["CopyTransformer", { "source_column" => "order_ref" }],
      "customer_name" => ["ConcatenateTransformer", { "source_columns" => %w[first last], "separator" => " " }],
      "order_date" => ["DateParseTransformer",
                       { "source_column" => "ordered_on", "format" => "%d %b %Y", "output_format" => "%Y-%m-%d" }],
      "sku" => ["SubstringTransformer", { "source_column" => "product_code", "start" => 4, "length" => 20 }],
      "quantity" => ["IntegerParseTransformer", { "source_column" => "qty" }],
      "line_total" => ["ArithmeticTransformer", { "source_columns" => %w[qty unit_price], "operator" => "*" }],
    }.freeze

    Configuration = Data.define(:input_file_type, :output_file_type, :transform_map)

    def self.seed!
      new.seed!
    end

    def seed!
      ActiveRecord::Base.transaction do
        existing = TransformMap.find_by(name: MAP_NAME)
        next configuration_for(existing) if existing

        input = create_file_type(INPUT_NAME, INPUT_COLUMNS, INPUT_VALIDATIONS)
        output = create_file_type(OUTPUT_NAME, OUTPUT_COLUMNS, OUTPUT_VALIDATIONS)
        map = TransformMap.create!(name: MAP_NAME, input_file_type: input, output_file_type: output)
        TRANSFORMATIONS.each do |target, (processor_class, settings)|
          map.transformations.create!(output_column: output.columns.find_by!(name: target), input_json: settings,
                                      column_transformer: catalog_entry(ColumnTransformer, processor_class))
        end
        configuration_for(map)
      end
    end

    private

    def create_file_type(name, column_names, validations)
      file_type = FileType.create!(name: name)
      column_names.each_with_index do |column_name, position|
        column = file_type.columns.create!(name: column_name, position: position)
        validations.fetch(column_name, []).each do |processor_class, settings|
          column.validations.create!(column_validator: catalog_entry(ColumnValidator, processor_class), input_json: settings)
        end
      end
      file_type
    end

    def catalog_entry(model, processor_class)
      model.find_by(processor_class: processor_class) or
        raise "#{model.name} #{processor_class} is missing; run bin/rails db:seed to load the operation catalogs"
    end

    def configuration_for(map)
      Configuration.new(input_file_type: map.input_file_type, output_file_type: map.output_file_type, transform_map: map)
    end
  end
end
