require "json"
require "time"
require "process"
require "system/user"

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
      Time.parse_local(value.read_string, "%Y-%m-%d %H:%M:%S")
    end
  end
end

class Entries < Array(Entry)
  def max_duration(min : Time::Span?, kernel : String?, generations : Int32?, now = Time.local) : Time::Span?
    kernel_pos = kernel.nil? ? 0 : self.index { |e| e.kernel_version == kernel }
    puts "WARNING: Target kernel #{kernel} not in any generation" if kernel_pos.nil?
    gen_pos = generations.nil? ? 0 : generations - 1
    # The oldest generation that has to be kept is either the one running the
    # target kernel or the generations-th most recent one, whichever is older.
    pos = kernel_pos.nil? || gen_pos > kernel_pos ? gen_pos : kernel_pos
    # If there are fewer generations than requested, all of them are kept.
    pos = self.size - 1 if pos >= self.size
    if pos >= 0
      entry = self[pos]
      keep_time = now - entry.date
      puts "Generation #{entry.generation} (##{pos + 1}) running #{entry.kernel_version == kernel ? "(target) " : ""}kernel #{entry.kernel_version} from #{entry.date} is age #{keep_time}#{min && keep_time < min ? " < #{min} min" : ""}"
      min && min > keep_time ? min : keep_time
    else
      nil
    end
  end
end

class ProfileHistoryItem
  getter version : Int32
  getter date : Time

  def initialize(@version, @date)
  end

  def self.parse(line : String) : ProfileHistoryItem?
    /^Version (?:\x1b\[[0-9;]*m)?(?<version>[0-9]+)(?:\x1b\[[0-9;]*m)? \((?<date>[0-9-]+)\)(?: <- [0-9]+)?:$/.match(line).try do |matches|
      date = Time.parse_local(matches["date"],"%Y-%m-%d")
      ProfileHistoryItem.new(matches["version"].to_i,date)
    end
  end
end

class SafeGC
  property kernel : String? = nil
  property min_time : Time::Span? = nil
  property generations : Int32? = nil
  property dry_run : Bool = false
  getter current_user : System::User { System::User.find_by(id: `id -u`) }

  def run
    entries = Entries.from_json(`nixos-rebuild list-generations --json`)
    keep = entries.max_duration(@min_time, @kernel, @generations)
    if keep
      keep_days = keep.days
      keep_days += 1 if keep_days.days < keep
      # nix-collect-garbage only accepts periods of at least one day.
      keep_days = 1 if keep_days < 1
      command = "nix-collect-garbage --delete-older-than #{keep_days}d"
      if @dry_run
        puts "Dry-run mode; skipping command: #{command}"
      else
        puts "+ #{command}"
        status = Process.run(command,
          shell: true, input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        raise CommandError.new if status.exit_code != 0
      end
    else
      puts "No entries to purge"
    end
  end

  private def run_as_command(user : String)
    args : Array(String) = ["sudo", "-u", user, Process.executable_path || PROGRAM_NAME]
    @generations.try { |generations| args += ["--generations", generations.to_s] }
    @min_time.try { |min_time| args += ["--days", min_time.days.to_s] }
    args << "--dry-run" if @dry_run
    @kernel.try do |kernel|
      args << "--keep-kernel"
      args << kernel.to_s unless @kernel == ""
    end
    args
  end

  def run_as(user : String)
    if user == current_user.username
      run
    else
      args = run_as_command(user)
      puts "#{args.join(" ")}"
      status = Process.run(args[0], args[1...],
        input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      raise CommandError.new if status.exit_code != 0
    end
  end
end
