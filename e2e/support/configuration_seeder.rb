# Creates the E2E-TEST configurations used by end-to-end tests and manual Postman testing.
# Two scenarios, each matching a folder of CSV files under e2e/fixtures/:
#   :basic         - supplier orders -> warehouse orders; the README example.
#   :comprehensive - event registrations -> attendee badges; uses every cataloged
#                    validator and transformer, plus an unmapped output column.
#
# Seeding is idempotent: a scenario whose map already exists (found by name) is returned as-is.
# To reset an edited configuration, run e2e:clean and seed again.
module E2e
  class ConfigurationSeeder
    NAME_PREFIX = "E2E-TEST".freeze

    # columns: name => [[validator class, input_json], ...]; transformations: output column =>
    # [transformer class, input_json]. Output columns without a transformation stay unmapped.
    SCENARIOS = {
      basic: {
        input_name: "#{NAME_PREFIX} Supplier orders",
        input_columns: {
          "order_ref" => [["RequiredValidator", nil]],
          "first" => [],
          "last" => [],
          "ordered_on" => [["DateValidator", { "format" => "%d %b %Y" }]],
          "product_code" => [["RegexValidator", { "pattern" => "\\ASKU-" }]],
          "qty" => [],
          "unit_price" => [],
        },
        output_name: "#{NAME_PREFIX} Warehouse orders",
        output_columns: {
          "order_id" => [],
          "customer_name" => [],
          "order_date" => [],
          "sku" => [],
          "quantity" => [["NumericRangeValidator", { "min" => 1 }]],
          "line_total" => [["NumericRangeValidator", { "min" => 0 }]],
        },
        map_name: "#{NAME_PREFIX} Supplier to warehouse",
        transformations: {
          "order_id" => ["CopyTransformer", { "source_column" => "order_ref" }],
          "customer_name" => ["ConcatenateTransformer", { "source_columns" => %w[first last], "separator" => " " }],
          "order_date" => ["DateParseTransformer",
                           { "source_column" => "ordered_on", "format" => "%d %b %Y", "output_format" => "%Y-%m-%d" }],
          "sku" => ["SubstringTransformer", { "source_column" => "product_code", "start" => 4, "length" => 20 }],
          "quantity" => ["IntegerParseTransformer", { "source_column" => "qty" }],
          "line_total" => ["ArithmeticTransformer", { "source_columns" => %w[qty unit_price], "operator" => "*" }],
        },
      },
      comprehensive: {
        input_name: "#{NAME_PREFIX} Event registrations",
        input_columns: {
          "reg_id" => [["RequiredValidator", nil], ["RegexValidator", { "pattern" => "\\AREG-T[0-9]{4}\\z" }]],
          "given_name" => [["RequiredValidator", nil], ["LengthValidator", { "max" => 20 }]],
          "family_name" => [["LengthValidator", { "min" => 0, "max" => 30 }]],
          "email" => [["RegexValidator", { "pattern" => "@example\\.test\\z" }]],
          "confirm_email" => [["StringComparisonValidator", { "other_column" => "email", "operator" => "==" }]],
          "registered_on" => [["DateValidator", { "format" => "%Y-%m-%d", "min" => "2026-01-01", "max" => "2026-12-31" }]],
          "event_on" => [["DateValidator", { "format" => "%d/%m/%Y" }]],
          # tickets <= group_size: also demonstrates that an unparseable number fails the comparison.
          "tickets" => [["NumericComparisonValidator", { "other_column" => "group_size", "operator" => "<=" }]],
          "ticket_price" => [],
          "discount" => [],
          "booking_fee" => [],
          "group_size" => [],
          "notes" => [],
        },
        output_name: "#{NAME_PREFIX} Attendee badges",
        output_columns: {
          "badge_id" => [["RegexValidator", { "pattern" => "\\AT[0-9]{4}\\z" }]],
          "full_name" => [],
          "display_name" => [["LengthValidator", { "max" => 40 }]],
          "badge_label" => [],
          "email" => [],
          "event_date" => [["DateValidator", { "format" => "%Y-%m-%d", "min" => "2026-01-01" }]],
          "tickets" => [["NumericRangeValidator", { "min" => 1, "max" => 10 }]],
          "ticket_price" => [["NumericRangeValidator", { "min" => 0 }]],
          "subtotal" => [],
          "net_price" => [],
          "price_with_fee" => [],
          "price_per_person" => [["NumericRangeValidator", { "min" => 0 }]],
          "notes_short" => [],
          "internal_ref" => [], # deliberately unmapped
        },
        map_name: "#{NAME_PREFIX} Registrations to badges",
        transformations: {
          "badge_id" => ["SubstringTransformer", { "source_column" => "reg_id", "start" => 4, "length" => 5 }],
          "full_name" => ["ConcatenateTransformer", { "source_columns" => %w[given_name family_name], "separator" => " " }],
          "display_name" => ["FormatStringTransformer",
                             { "source_columns" => %w[given_name family_name],
                               "format" => "%{family_name}, %{given_name}" }],
          "badge_label" => ["FormatStringTransformer",
                            { "source_columns" => %w[given_name], "format" => "%{given_name} - 100%% fake" }],
          "email" => ["CopyTransformer", { "source_column" => "email" }],
          "event_date" => ["DateParseTransformer", { "source_column" => "event_on", "format" => "%d/%m/%Y" }],
          "tickets" => ["IntegerParseTransformer", { "source_column" => "tickets" }],
          "ticket_price" => ["DecimalParseTransformer", { "source_column" => "ticket_price" }],
          "subtotal" => ["ArithmeticTransformer", { "source_columns" => %w[tickets ticket_price], "operator" => "*" }],
          "net_price" => ["ArithmeticTransformer", { "source_columns" => %w[ticket_price discount], "operator" => "-" }],
          "price_with_fee" => ["ArithmeticTransformer", { "source_columns" => %w[ticket_price booking_fee], "operator" => "+" }],
          "price_per_person" => ["ArithmeticTransformer",
                                 { "source_columns" => %w[ticket_price group_size], "operator" => "/", "scale" => 2 }],
          "notes_short" => ["TruncateTransformer", { "source_column" => "notes", "length" => 15 }],
        },
      },
    }.freeze

    Configuration = Data.define(:input_file_type, :output_file_type, :transform_map)

    def self.seed!(scenario)
      new(scenario).seed!
    end

    def self.seed_all!
      SCENARIOS.keys.to_h { |scenario| [scenario, seed!(scenario)] }
    end

    def initialize(scenario)
      @definition = SCENARIOS.fetch(scenario)
    end

    def seed!
      ActiveRecord::Base.transaction do
        existing = TransformMap.find_by(name: @definition[:map_name])
        next configuration_for(existing) if existing

        input = create_file_type(@definition[:input_name], @definition[:input_columns])
        output = create_file_type(@definition[:output_name], @definition[:output_columns])
        map = TransformMap.create!(name: @definition[:map_name], input_file_type: input, output_file_type: output)
        @definition[:transformations].each do |target, (processor_class, settings)|
          map.transformations.create!(output_column: output.columns.find_by!(name: target), input_json: settings,
                                      column_transformer: catalog_entry(ColumnTransformer, processor_class))
        end
        configuration_for(map)
      end
    end

    private

    def create_file_type(name, columns)
      file_type = FileType.create!(name: name)
      # Create every column before any validation: same-row comparison rules reference other columns.
      created = columns.keys.each_with_index.to_h do |column_name, position|
        [column_name, file_type.columns.create!(name: column_name, position: position)]
      end
      columns.each do |column_name, validations|
        validations.each do |processor_class, settings|
          created.fetch(column_name)
                 .validations.create!(column_validator: catalog_entry(ColumnValidator, processor_class), input_json: settings)
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
