class CreateConversionRuns < ActiveRecord::Migration[8.1]
  STATUSES = %w[queued running succeeded rejected failed].freeze

  def change
    create_table :conversion_runs do |t|
      t.references :data_file, null: false, foreign_key: true
      t.references :transform_map, null: false, foreign_key: true
      # Fingerprint of the map and both file types' configuration when the run was requested.
      t.string :configuration_digest, null: false
      t.string :status, null: false, default: "queued"
      t.integer :accepted_rows
      t.integer :rejected_rows
      t.integer :error_count
      t.text :failure_reason
      t.datetime :started_at
      t.datetime :heartbeat_at
      t.datetime :finished_at
      t.timestamps
    end

    add_check_constraint :conversion_runs,
                         "status IN (#{STATUSES.map { |status| "'#{status}'" }.join(', ')})",
                         name: "conversion_runs_status_check"
    # At most one reusable run per data file, map, and configuration; failed runs can be retried by a new request.
    add_index :conversion_runs, [:data_file_id, :transform_map_id, :configuration_digest], unique: true,
              where: "status <> 'failed'", name: "index_conversion_runs_reusable"
    add_index :conversion_runs, :heartbeat_at, where: "status = 'running'", name: "index_conversion_runs_running"
  end
end
