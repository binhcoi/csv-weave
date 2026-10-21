class CreateColumnValidators < ActiveRecord::Migration[8.1]
  def change
    create_table :column_validators do |t|
      t.text :description
      t.string :processor_class, null: false

      t.timestamps
      t.index :processor_class, unique: true
    end
  end
end
