class CreateTransformations < ActiveRecord::Migration[8.1]
  def change
    create_table :transformations do |t|
      t.references :transform_map, null: false, foreign_key: true
      t.references :output_column, null: false, foreign_key: { to_table: :columns }
      t.references :column_transformer, null: false, foreign_key: true
      t.jsonb :input_json, null: false, default: {}

      t.timestamps

      t.index [:transform_map_id, :output_column_id], unique: true
    end
  end
end
