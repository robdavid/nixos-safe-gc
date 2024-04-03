require "yaml"
require "time"

y = YAML.parse(`nixos-rebuild list-generations --json`)
#puts y
kernel = `uname -r`.strip
pp! kernel
matching = y.as_a.find {|entry| entry["kernelVersion"].as_s == kernel }
days_to_keep = 21
if matching
    keep_generation = matching["generation"].as_i
    keep_date = Time.parse_rfc3339(matching["date"].as_s)
    keep_days = (Time.utc.at_beginning_of_day - keep_date.at_beginning_of_day).days + 1
    pp! keep_generation, keep_date, keep_days
    days_to_keep = keep_days if keep_days > days_to_keep
else
    puts "WARNING: current kernel not in any generation"
end
puts "nix-collect-garbage --delete-older-than #{days_to_keep}d"
