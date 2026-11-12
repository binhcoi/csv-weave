class CreateDataFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :data_files do |t|
      t.references :file_type, null: false, foreign_key: true
      t.timestamps
    end
  end
end
