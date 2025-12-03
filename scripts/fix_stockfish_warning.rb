#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fix the frozen string literal warning in the stockfish gem
# This script finds the stockfish gem, shows what will be changed, and applies the fix
#
# Usage:
#   ruby scripts/fix_stockfish_warning.rb
#
# The script will:
#   1. Find the stockfish gem installation (works regardless of gem location)
#   2. Show a preview of what will be changed
#   3. Ask for permission before modifying the file
#   4. Create a backup of the original file
#   5. Add '# frozen_string_literal: true' at the top of the gem file
#   6. Fix mutable string issues (e.g., output = "" to output = String.new)
#
# Note: If you reinstall the gem, you'll need to run this script again.

require 'rubygems'
require 'fileutils'

def find_stockfish_gem
  # Try to load the stockfish gem to find its location
  begin
    require 'stockfish'
    spec = Gem.loaded_specs['stockfish']
    return spec.gem_dir if spec
  rescue LoadError
    # Gem not loaded yet, try to find it
  end

  # Alternative: search installed gems
  Gem::Specification.each do |spec|
    return spec.gem_dir if spec.name == 'stockfish'
  end

  nil
end

def get_target_file(gem_dir)
  File.join(gem_dir, 'lib', 'stockfish', 'engine.rb')
end

def check_file_exists(file_path)
  return true if File.exist?(file_path)

  warn "Error: File not found: #{file_path}"
  false
end

def needs_fix?(file_path)
  return false unless File.exist?(file_path)

  content = File.read(file_path)

  # Check if file already has frozen_string_literal comment
  has_frozen_comment = content.lines.any? { |line| line.strip.start_with?('# frozen_string_literal') }

  # Check if mutable string fix is needed (output = "" should be output = String.new)
  needs_mutable_fix = content.include?('output = ""')

  # Fix needed if either the comment is missing or mutable string needs fixing
  !has_frozen_comment || needs_mutable_fix
end

def apply_fix(file_path)
  content = File.read(file_path)
  fixed_content = content.dup

  # Step 1: Add frozen_string_literal comment if missing
  has_frozen_comment = fixed_content.lines.any? { |line| line.strip.start_with?('# frozen_string_literal') }

  unless has_frozen_comment
    # Check if file starts with shebang - if so, add comment after shebang
    if fixed_content.start_with?('#!')
      # Find end of shebang line
      first_newline = fixed_content.index("\n")
      if first_newline
        # Insert after shebang line
        fixed_content = "#{fixed_content[0..first_newline]}# frozen_string_literal: true\n#{fixed_content[(first_newline + 1)..]}"
      else
        # No newline after shebang (unlikely), just prepend
        fixed_content = "# frozen_string_literal: true\n#{fixed_content}"
      end
    else
      # Add frozen_string_literal comment at the very beginning
      fixed_content = "# frozen_string_literal: true\n#{fixed_content}"
    end
  end

  # Step 2: Fix mutable string issues - replace output = "" with output = String.new
  # This is needed because with frozen_string_literal, "" is frozen and can't be modified with <<
  fixed_content = fixed_content.gsub(/\boutput = ""/, 'output = String.new')

  # Write back to file
  File.write(file_path, fixed_content)
end

def show_preview(file_path, will_add_frozen_comment)
  lines = File.readlines(file_path)
  has_shebang = lines.first&.start_with?('#!')

  puts "\nPreview of first 10 lines before fix:"
  puts '-' * 60
  lines.first(10).each_with_index do |line, i|
    puts "#{i + 1}: #{line.chomp}"
  end
  puts '-' * 60

  puts "\nPreview after fix:"
  puts '-' * 60
  line_num = 1
  if has_shebang && will_add_frozen_comment
    puts "#{line_num}: #{lines[0].chomp}"
    line_num += 1
    puts "#{line_num}: # frozen_string_literal: true"
    line_num += 1
    start_idx = 1
  elsif will_add_frozen_comment
    puts "#{line_num}: # frozen_string_literal: true"
    line_num += 1
    start_idx = 0
  else
    start_idx = 0
  end

  remaining_lines = lines[start_idx, 10 - (line_num - 1)]
  remaining_lines.each do |line|
    puts "#{line_num}: #{line.chomp}"
    line_num += 1
  end
  puts '-' * 60
end

# Main execution
puts 'Stockfish Gem Warning Fix Script'
puts '=' * 60

# Find the gem
puts "\nSearching for stockfish gem..."
gem_dir = find_stockfish_gem

unless gem_dir
  warn 'Error: Could not find stockfish gem. Is it installed?'
  exit 1
end

puts "Found stockfish gem at: #{gem_dir}"

target_file = get_target_file(gem_dir)

unless check_file_exists(target_file)
  warn 'Error: Could not find engine.rb file'
  exit 1
end

puts "Target file: #{target_file}"

# Check what needs fixing
content = File.read(target_file)
has_frozen_comment = content.lines.any? { |line| line.strip.start_with?('# frozen_string_literal') }
needs_mutable_fix = content.include?('output = ""')

# If everything is already fixed, exit
if has_frozen_comment && !needs_mutable_fix
  puts "\n✓ File already has 'frozen_string_literal: true' comment and mutable string fixes."
  puts 'No fix needed!'
  exit 0
end

# Determine what fixes are needed
fixes = []
fixes << "Add '# frozen_string_literal: true' comment" unless has_frozen_comment
fixes << 'Fix mutable string (output = "" -> output = String.new)' if needs_mutable_fix

puts "\nFixes to apply:"
fixes.each { |fix| puts "  - #{fix}" }

# Show preview
show_preview(target_file, !has_frozen_comment)

# Ask for permission
puts "\nThis will modify the stockfish gem file to:"
fixes.each { |fix| puts "  - #{fix}" }
puts "\nWARNING: This modifies a gem file. If you reinstall the gem, the change will be lost."
puts "\nDo you want to proceed? (yes/no): "
response = $stdin.gets.chomp.downcase

unless %w[y yes].include?(response)
  puts 'Aborted.'
  exit 0
end

# Create backup
backup_file = "#{target_file}.backup"
FileUtils.cp(target_file, backup_file)
puts "\nCreated backup: #{backup_file}"

# Apply fix
puts 'Applying fix...'
apply_fix(target_file)

puts "\n✓ Fix applied successfully!"
puts "\nThe warning should no longer appear when loading the stockfish gem."
puts 'The frozen string issues that cause test failures have also been fixed.'
puts 'If you reinstall the gem, you can run this script again to reapply the fix.'
