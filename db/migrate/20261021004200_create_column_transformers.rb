class CreateColumnTransformers < ActiveRecord::Migration[8.1]
  def change
    create_table :column_transformers do |t|
      t.text :description
      t.string :processor_class, null: false
      t.jsonb :input_schema

      t.timestamps
      t.index :processor_class, unique: true
    end
  end
end
