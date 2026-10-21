# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_20_235848) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "column_validators", force: :cascade do |t|
    t.text "description"
    t.string "processor_class", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "columns", force: :cascade do |t|
    t.bigint "file_type_id", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["file_type_id", "name"], name: "index_columns_on_file_type_id_and_name", unique: true
    t.index ["file_type_id", "position"], name: "index_columns_on_file_type_id_and_position", unique: true
    t.index ["file_type_id"], name: "index_columns_on_file_type_id"
    t.check_constraint "\"position\" >= 0", name: "nonnegative_position"
  end

  create_table "file_types", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transform_maps", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.bigint "input_file_type_id", null: false
    t.bigint "output_file_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["input_file_type_id"], name: "index_transform_maps_on_input_file_type_id"
    t.index ["output_file_type_id"], name: "index_transform_maps_on_output_file_type_id"
  end

  add_foreign_key "columns", "file_types"
  add_foreign_key "transform_maps", "file_types", column: "input_file_type_id"
  add_foreign_key "transform_maps", "file_types", column: "output_file_type_id"
end
