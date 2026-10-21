class CreateColumns < ActiveRecord::Migration[8.1]
  def change
    create_table :columns do |t|
      t.references :file_type, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false
      t.text :description

      t.timestamps
      t.index [:file_type_id, :position], unique: true
      t.index [:file_type_id, :name], unique: true
      t.check_constraint "position >= 0", name: "nonnegative_position"
    end
  end
end
