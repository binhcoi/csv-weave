FactoryBot.define do
  factory :column_transformer do
    processor_class { "CopyTransformer" }
    description { "Copies a source value" }
    input_schema do
      {
        "type" => "object",
        "properties" => {
          "source_column" => { "type" => "string", "minLength" => 1 },
        },
        "required" => ["source_column"],
        "additionalProperties" => false,
      }
    end
  end
end
