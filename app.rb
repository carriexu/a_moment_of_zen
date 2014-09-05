require 'sinatra/base'
require 'json'
require 'redis'
require 'httparty'
require 'pry'

class App < Sinatra::Base

  ########################
  # Configuration
  ########################

  configure do
    enable :logging
    enable :method_override
    enable :sessions
    uri = URI.parse(ENV["REDISTOGO_URL"])
    $redis = Redis.new({:host => uri.host,
                        :port => uri.port,
                        :password => uri.password})
  end

  before do
    logger.info "Request Headers: #{headers}"
    logger.warn "Params: #{params}"
  end

  after do
    logger.info "Response Headers: #{response.headers}"
  end

  ########################
  # API KEYS
  ########################

  NYTIMES_MOST_POPULAR_API_KEYS = "85eb47a4b49d424d01237d5a8f3cd55b:18:62890239"

  ########################
  # Routes
  ########################

  get('/') do
    render(:erb, :index)
  end

  get('/profile') do
    @profiles = []
    $redis.keys('*profile*').each do |key|
      @profiles << get_model_from_redis(key)
    end
    render(:erb, :profile)
  end

  get('/feed') do
    response = HTTParty.get("http://api.nytimes.com/svc/mostpopular/v2/mostviewed/all-sections/1.json?api-key=#{NYTIMES_MOST_POPULAR_API_KEYS}")
    parsed_response = JSON.parse response.to_json
    # binding.pry
    @first_article_url = parsed_response["results"][0]["url"]
    @first_article_title = parsed_response["results"][0]["title"]
    render(:erb, :feed)
  end

  def get_model_from_redis(redis_id)
    model = JSON.parse($redis.get(redis_id))
    model
  end
end
