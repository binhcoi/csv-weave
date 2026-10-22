class CreateValidations < ActiveRecord::Migration[8.1]
  def change
    create_table :validations do |t|
      t.references :column, null: false, foreign_key: true
      t.references :column_validator, null: false, foreign_key: true
      t.jsonb :input_json, default: {}

      t.timestamps
    end
  end
end
