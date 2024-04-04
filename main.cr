require "json"
require "time"
require "option_parser"

struct Entry
  include JSON::Serializable

  property generation : Int32
  
  property date : Time

  @[JSON::Field(key: "nixosVersion")]
  property nixos_version : String

  @[JSON::Field(key: "kernelVersion")]
  property kernel_version : String

  @[JSON::Field(key: "configurationRevision")]
  property configuration_revision : String

  property specialisations : Array(String)

  property current : Bool
end

kernel = ""
days_to_keep = 1
generations_to_keep = 1
begin
  OptionParser.parse do |parser|
    parser.banner = "Usage: nixos-safe-gc [options]"
    parser.on("-k VERSION","--keep-kernel VERSION", 
      "Keep generation with the given kernel version (defaults to current kernel)") {|k| kernel = k }
    parser.on("-d DAYS","--days DAYS",
      "Keep at least the given number of days worth of generations") { |n| days_to_keep = n.to_i }
    parser.on("-g GENERATIONS","--generations GENERATIONS",
      "Keep at least the given number of generations") {|n| generations_to_keep = n.to_i }
    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit(1)
    end
  end

  kernel = `uname -r`.strip if kernel == ""
  entries = Array(Entry).from_json(`nixos-rebuild list-generations --json`)
rescue e : JSON::ParseException
  STDERR.print("nixos-safe-gc: cannot parse result from nixos-rebuild: #{e}")
  exit(1)
rescue e : ArgumentError
  STDERR.print("nixos-safe-gc: #{e}")
  exit(1)
end

kernel_pos = entries.index { |e| e.kernel_version == kernel }
puts "WARNING: current kernel not in any generation" if kernel_pos.nil?

pos = kernel_pos.nil? || kernel_pos+1 < generations_to_keep ? generations_to_keep : kernel_pos

if pos < entries.size
  keep_days = (Time.utc.at_beginning_of_day - entries[pos].date.at_beginning_of_day).days + 1
  days_to_keep = keep_days if keep_days > days_to_keep
  pp! entries[pos].generation, entries[pos].date, keep_days
  puts "nix-collect-garbage --delete-older-than #{days_to_keep}d"
else
  puts "No entries to purge"
end
