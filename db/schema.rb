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

ActiveRecord::Schema[8.1].define(version: 2026_10_22_002423) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "column_transformers", force: :cascade do |t|
    t.text "description"
    t.string "processor_class", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["processor_class"], name: "index_column_transformers_on_processor_class", unique: true
  end

  create_table "column_validators", force: :cascade do |t|
    t.text "description"
    t.string "processor_class", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["processor_class"], name: "index_column_validators_on_processor_class", unique: true
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

  create_table "transformations", force: :cascade do |t|
    t.bigint "transform_map_id", null: false
    t.bigint "output_column_id", null: false
    t.bigint "column_transformer_id", null: false
    t.jsonb "input_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["column_transformer_id"], name: "index_transformations_on_column_transformer_id"
    t.index ["output_column_id"], name: "index_transformations_on_output_column_id"
    t.index ["transform_map_id", "output_column_id"], name: "index_transformations_on_transform_map_id_and_output_column_id", unique: true
    t.index ["transform_map_id"], name: "index_transformations_on_transform_map_id"
  end

  create_table "validations", force: :cascade do |t|
    t.bigint "column_id", null: false
    t.bigint "column_validator_id", null: false
    t.jsonb "input_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["column_id"], name: "index_validations_on_column_id"
    t.index ["column_validator_id"], name: "index_validations_on_column_validator_id"
  end

  add_foreign_key "columns", "file_types"
  add_foreign_key "transform_maps", "file_types", column: "input_file_type_id"
  add_foreign_key "transform_maps", "file_types", column: "output_file_type_id"
  add_foreign_key "transformations", "column_transformers"
  add_foreign_key "transformations", "columns", column: "output_column_id"
  add_foreign_key "transformations", "transform_maps"
  add_foreign_key "validations", "column_validators"
  add_foreign_key "validations", "columns"
end
