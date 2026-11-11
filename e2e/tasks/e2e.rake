# End-to-end testing tasks. Run them inside this worktree's container, e.g.:
#   docker exec <container> bin/rails e2e:seed
E2E_PREFIX = "E2E-TEST".freeze

def refuse_in_production!
  abort "e2e tasks are disabled in production" if Rails.env.production?
end

namespace :e2e do
  desc "Create the #{E2E_PREFIX} file types, validations, and transformation map"
  task seed: :environment do
    refuse_in_production!
    require Rails.root.join("e2e/support/configuration_seeder")

    configuration = E2e::ConfigurationSeeder.seed!
    puts "input_file_type_id:  #{configuration.input_file_type.id}  (#{configuration.input_file_type.name})"
    puts "output_file_type_id: #{configuration.output_file_type.id}  (#{configuration.output_file_type.name})"
    puts "transform_map_id:    #{configuration.transform_map.id}  (#{configuration.transform_map.name})"
  end

  desc "Delete all #{E2E_PREFIX} records, their uploaded files, and their runs"
  task clean: :environment do
    refuse_in_production!

    file_types = FileType.where("name LIKE ?", "#{E2E_PREFIX}%")
    maps = TransformMap.where("name LIKE ?", "#{E2E_PREFIX}%")
      .or(TransformMap.where(input_file_type: file_types)).or(TransformMap.where(output_file_type: file_types))
    data_files = DataFile.where(file_type: file_types)

    counts = {}
    ConversionRun.where(transform_map: maps).or(ConversionRun.where(data_file: data_files)).find_each do |run|
      run.error_report.purge
      run.output.purge
      counts["conversion runs"] = counts.fetch("conversion runs", 0) + run.destroy!.then { 1 }
    end
    ValidationRun.where(file_type: file_types).or(ValidationRun.where(data_file: data_files)).find_each do |run|
      run.error_report.purge
      counts["validation runs"] = counts.fetch("validation runs", 0) + run.destroy!.then { 1 }
    end
    data_files.find_each do |data_file|
      data_file.file.purge
      counts["data files"] = counts.fetch("data files", 0) + data_file.destroy!.then { 1 }
    end
    counts["transform maps"] = maps.destroy_all.size
    counts["file types"] = file_types.destroy_all.size

    counts.each { |label, count| puts "deleted #{count} #{label}" }
  end

  desc "Run the Postman collection with Newman against this container's own server"
  task :newman do
    collection = File.expand_path("../postman/CSVWeave.postman_collection.json", __dir__)
    abort "missing #{collection}" unless File.exist?(collection)

    reports = File.expand_path("../reports", __dir__)
    FileUtils.mkdir_p(reports)
    sh "newman", "run", collection,
       "--env-var", "baseUrl=#{ENV.fetch('E2E_BASE_URL', 'http://localhost:3000')}",
       "--reporters", "cli,junit", "--reporter-junit-export", File.join(reports, "newman.xml")
  end
end
