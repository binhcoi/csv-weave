class CreateTransformMaps < ActiveRecord::Migration[8.1]
  def change
    create_table :transform_maps do |t|
      t.string :name, null: false
      t.text :description
      t.references :input_file_type, null: false, foreign_key: { to_table: :file_types }
      t.references :output_file_type, null: false, foreign_key: { to_table: :file_types }

      t.timestamps
    end
  end
end
