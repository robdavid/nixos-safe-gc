require "json"
require "time"
require "option_parser"
require "process"

class CommandError < Exception
  def initialize(message = "Command error")
    super(message)
  end
end

struct Entry
  include JSON::Serializable

  property generation : Int32

  @[JSON::Field(key: "date", converter: Entry::TimeConverter)]
  property date : Time

  @[JSON::Field(key: "nixosVersion")]
  property nixos_version : String

  @[JSON::Field(key: "kernelVersion")]
  property kernel_version : String

  @[JSON::Field(key: "configurationRevision")]
  property configuration_revision : String

  property specialisations : Array(String)

  property current : Bool

  class TimeConverter

    def self.from_json(value : JSON::PullParser) : Time
      Time.parse_local(value.read_string,"%Y-%m-%d %H:%M:%S")
    end

  end

end

class Entries < Array(Entry)
  def max_duration(min : Time::Span, kernel : String?, generations : Int32, now = Time.utc) : Time::Span?
    kernel_pos = kernel.nil? ? 0 : self.index { |e| e.kernel_version == kernel }
    puts "WARNING: Target kernel #{kernel} not in any generation" if kernel_pos.nil?
    pos = kernel_pos.nil? || kernel_pos + 1 < generations ? generations - 1 : kernel_pos
    if pos < self.size
      entry = self[pos]
      keep_time = now - entry.date
      puts "Generation #{entry.generation} (##{pos + 1}) running #{entry.kernel_version == kernel ? "(target) " : ""}kernel #{entry.kernel_version} from #{entry.date} is age #{keep_time}#{keep_time < min ? " < #{min} min" : ""}"
      keep_time < min ? min : keep_time
    else
      nil
    end
  end
end

kernel = nil
min_time = 1.nanosecond
generations = 1
dry_run = false
begin
  OptionParser.parse do |parser|
    parser.banner = "Usage: nixos-safe-gc [options]"
    parser.on("-k [VERSION]", "--keep-kernel [VERSION]",
      "Keep generation with the given kernel version (defaults to current kernel)") { |k| kernel = (k == "" ? `uname -r`.strip : k) }
    parser.on("-d DAYS", "--days DAYS",
      "Keep at least the given number of days worth of generations") { |n| min_time = n.to_i.days }
    parser.on("-g GENERATIONS", "--generations GENERATIONS",
      "Keep at least the given number of generations") { |n| generations = n.to_i }
    parser.on("-R", "--dry-run", "Don't perform a GC, but show what would be done") { dry_run = true }
    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit(1)
    end
  end

  entries = Entries.from_json(`nixos-rebuild list-generations --json`)
  keep = entries.max_duration(min_time, kernel, generations)
  if keep
    keep_days = keep.days
    keep_days += 1 if keep_days.days < keep
    command = "nix-collect-garbage --delete-older-than #{keep_days}d"
    if dry_run
      puts "Dry-run mode; skipping command: #{command}"
    else
      puts "+ #{command}"
      status = Process.run(command, 
        shell: true, input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      raise CommandError.new() if status.exit_code != 0 
    end
  else
    puts "No entries to purge"
  end

rescue e : JSON::ParseException
  STDERR.print("nixos-safe-gc: cannot parse result from nixos-rebuild: #{e}")
  exit(1)
rescue e : ArgumentError
  STDERR.print("nixos-safe-gc: #{e}")
  exit(1)
rescue e : CommandError
  exit(1) 
rescue e : Exception
  STDERR.print("nixos-safe-gc: #{e}")
  exit(2)
end

