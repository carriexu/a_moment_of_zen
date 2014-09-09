require 'redis'
require 'json'
require 'pry' if ENV["RACK_ENV"] == "development"
require 'uri'

# configure redis connection
uri = URI.parse(ENV["REDISTOGO_URL"])
$redis = Redis.new({:host => uri.host,
                    :port => uri.port,
                    :password => uri.password})

# clear out the db
$redis.flushdb
# first set a counter, which starts at 0
$redis.set("counter", 0)

file_contents = File.read('profile_data.json')
ruby_object   = JSON.parse file_contents

ruby_object["profile_data"].each do |profile|
  index = $redis.incr("counter")
  profile[:id] = index
  $redis.set("profile:#{index}", profile.to_json)
end

