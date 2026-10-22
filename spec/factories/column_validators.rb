FactoryBot.define do
  factory :column_validator do
    processor_class { "RequiredValidator" }
    description { "Column requires a value" }
    input_schema { nil }
  end
end
