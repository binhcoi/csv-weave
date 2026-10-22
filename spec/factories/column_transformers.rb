FactoryBot.define do
  factory :column_transformer do
    processor_class { "CopyTransformer" }
    description { "Copies a source value" }
    input_schema do
      {
        "type" => "object",
        "properties" => { "name" => { "type" => "string", "minLength" => 1 } },
        "required" => ["name"],
        "additionalProperties" => false,
      }
    end
  end
end
