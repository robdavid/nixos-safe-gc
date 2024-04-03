require "json"
require "time"

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

entries = Array(Entry).from_json(`nixos-rebuild list-generations --json`)
kernel = `uname -r`.strip
pp! kernel
matching = entries.find { |e| e.kernel_version == kernel }
days_to_keep = 21
if matching
    keep_days = (Time.utc.at_beginning_of_day - matching.date.at_beginning_of_day).days + 1
    pp! matching.generation, matching.date, keep_days
    days_to_keep = keep_days if keep_days > days_to_keep
else
    puts "WARNING: current kernel not in any generation"
end
puts "nix-collect-garbage --delete-older-than #{days_to_keep}d"
