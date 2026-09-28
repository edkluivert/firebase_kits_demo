# Adds ios/Runner/GoogleService-Info.plist to the Runner target's bundle
# resources (idempotent). Run: ruby tool/add_google_service_plist.rb
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'
group = project.main_group.find_subpath('Runner', false) or abort 'Runner group not found'
path = 'GoogleService-Info.plist'
abort "ios/Runner/#{path} is missing" unless File.exist?("ios/Runner/#{path}")

file_ref = group.files.find { |f| f.path == path } || group.new_file(path)
unless runner.resources_build_phase.files_references.include?(file_ref)
  runner.add_resources([file_ref])
end
project.save
puts "GoogleService-Info.plist is in the Runner target's Copy Bundle Resources"
