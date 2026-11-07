require "yaml"
require "file"

content = File.read("#{__DIR__}/shard.yml")
data = YAML.parse(content)
puts data["version"]
