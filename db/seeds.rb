# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

validators = [
  {
    processor_class: "RequiredValidator",
    description: "Validate a column has a nonblank value",
  },
]

transformers = [
  {
    processor_class: "CopyTransformer",
    description: "Copy the value of an input column to an output column",
  },
]

ColumnValidator.transaction do
  validators.each do |attributes|
    validator = ColumnValidator.find_or_initialize_by(
      processor_class: attributes.fetch(:processor_class),
    )
    validator.update!(attributes)
  end
end

ColumnTransformer.transaction do
  transformers.each do |attributes|
    transformer = ColumnTransformer.find_or_initialize_by(
      processor_class: attributes.fetch(:processor_class),
    )
    transformer.update!(attributes)
  end
end
