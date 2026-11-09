require "digest"
require "json"

# Fingerprint of everything that affects converting a file with a transform map: which file types
# the map connects, both file types' validation configuration, and the map's transformation rules
# with the transformer catalog entries they use. Names and descriptions are excluded.
class ConversionConfigurationDigest
  def self.for(transform_map_id)
    input_id, output_id = TransformMap.where(id: transform_map_id).pick(:input_file_type_id, :output_file_type_id)
    transformations = Transformation.where(transform_map_id: transform_map_id).order(:id)
                                    .pluck(:id, :output_column_id, :column_transformer_id, :input_json)
    transformers = ColumnTransformer.where(id: transformations.map { |row| row[2] }.uniq)
                                    .order(:id).pluck(:id, :processor_class, :input_schema)

    Digest::SHA256.hexdigest(JSON.generate([
      input_id, output_id,
      FileTypeConfigurationDigest.for(input_id), FileTypeConfigurationDigest.for(output_id),
      transformations, transformers,
    ]))
  end
end
