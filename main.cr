require "time"
require "option_parser"
require "./src/safegc"

VERSION = {{ run("./version").stringify }}

gc = SafeGC.new

users = [] of String
begin
  OptionParser.parse do |parser|
    parser.banner = "Usage: nixos-safe-gc [options]"
    parser.on("-k [VERSION]", "--keep-kernel [VERSION]",
      "Keep generation with the given kernel version (defaults to current kernel)") do |k|
      gc.kernel = (k == "" ? `uname -r`.strip : k)
    end
    parser.on("-d DAYS", "--days DAYS",
      "Keep at least the given number of days worth of generations") { |n| gc.min_time = n.to_i.days }
    parser.on("-g GENERATIONS", "--generations GENERATIONS",
      "Keep at least the given number of generations") { |n| gc.generations = n.to_i }
    parser.on("-R", "--dry-run", "Don't perform a GC, but show what would be done") { gc.dry_run = true }
    parser.on("-u USER", "--user USER", "One or more users to run the garbage collection for") { |u| users << u }
    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit(0)
    end
    parser.on("-v", "--version", "Show version") do
      puts VERSION
      exit(0)
    end
  end

  if users.empty?
    gc.run
  else
    users.each { |user| gc.run_as(user) }
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
