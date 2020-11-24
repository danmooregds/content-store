namespace :routes do
  desc "Register routes for a content item"
  task :register, %w[base_path] => %w[environment] do |_, args|
    item = ContentItem.find_by!(base_path: args[:base_path])
    item.route_set.register!
  end

  desc "Delete routes for a content item"
  task :delete, %w[base_path] => %w[environment] do |_, args|
    item = ContentItem.find_by!(base_path: args[:base_path])
    item.route_set.delete!
  end

  desc "What plek is running?"
  task plek: :environment do
    puts "This is what plek is running...."
    puts Plek.current.find("router-api")
  end
end
