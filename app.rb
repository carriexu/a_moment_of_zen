require 'sinatra/base'
require 'json'
require 'redis'
require 'httparty'
require 'pry'
require 'securerandom'
require 'twitter'

class App < Sinatra::Base

  ########################
  # Configuration
  ########################

  configure do
    enable :logging
    enable :method_override
    enable :sessions
    set :session_secret, 'super_secret'
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
  # when registering for apis
  # website url: http://127.0.0.1:9292
  # Callback URL: http://127.0.0.1:9292/oauth_callback

  NYTIMES_MOST_POPULAR_API_KEYS = "85eb47a4b49d424d01237d5a8f3cd55b:18:62890239"
  NYTIMES_ARTICLE_SEARCH_API_KEYS = "a7cae18610fa4d1fb5b005b13a6552f5:16:62890239"
  TWITTER_API_KEYS = "uOuLYN472FTMDFpfnCv3C5iql"
  TWITTER_API_SECRET = "QBlplAUdkdJIpGQLl3uOMG0HFgKv1aoSU8RiuVniYRHOF2zRVJ"
  TWITTER_ACCESS_TOKEN = "509730170-cACt75aeSelrZKpvUcMuGJrH2XIgcIK7GnUrw2rq"
  TWITTER_ACCESS_TOKEN_SECRET = "L1UixxGbq1kLRPdN00WunhIZczDbw8OdzGzCgiNqZvQUv"
  WUNDERGROUND_API_KEYS = "414d6ac14863ad60"
  INSTAGRAM_CLIENT_ID = "b668170700ab4a2c8793bdcfcc875806"
  INSTAGRAM_CLIENT_SECRET = "175b08336c364ea18013ed373dd96f0b"
  INSTAGRAM_REDIRECT_URL = "http://127.0.0.1:9292/oauth_callback"

  ########################
  # Routes
  ########################

  get('/') do
    # Instagram OAuth
    base_url = "https://api.instagram.com/oauth/authorize"
    scope = "user"
    state = SecureRandom.urlsafe_base64
    # storing state in session because we need to compare it in a later request
    session[:state] = state

    @uri = "#{base_url}?client_id=#{INSTAGRAM_CLIENT_ID}&redirect_uri=#{INSTAGRAM_REDIRECT_URL}&response_type=code&state=#{state}"
    render(:erb, :index)
  end

  get('/oauth_callback') do
    # Instagram OAuth
    # puts session
    # state = params[:state]
    code = params[:code]
    # compare the states to ensure the information is from who we think it is
    if session[:state] == params[:state]
      # send a post
    # binding.pry
      response = HTTParty.post("https://api.instagram.com/oauth/access_token",
                              :body => {
                              client_id: INSTAGRAM_CLIENT_ID,
                              client_secret: INSTAGRAM_CLIENT_SECRET,
                              grant_type: "authorization_code",
                              code: code,
                              redirect_uri: INSTAGRAM_REDIRECT_URL
                              },
                              :headers =>{
                                "Accept" => "application/json"
                                })
        session[:access_token] = response["access_token"]
      end
    redirect to("/")
  end

  get('/logout') do
    session[:access_token] = nil
    redirect to('/')
  end

  get('/profile') do
    @profiles = []
    $redis.keys('*profile*').each do |key|
      @profiles << get_model_from_redis(key)
    end
    render(:erb, :profile)
  end

  get('/profile/edit') do
    @profiles = []
    $redis.keys('*profile*').each do |key|
      @profiles << get_model_from_redis(key)
    end
    render(:erb, :edit_form)
  end


  get('/feed') do
    profile = JSON.parse $redis.get("profile:1")

    response = HTTParty.get("http://api.nytimes.com/svc/mostpopular/v2/mostviewed/all-sections/1.json?api-key=#{NYTIMES_MOST_POPULAR_API_KEYS}")
    @parsed_response = JSON.parse response.to_json

    # binding.pry
    @city = profile["city"].gsub(" ", "%20")
    @state = profile["state"].gsub(" ", "%20")
    response = HTTParty.get("http://api.wunderground.com/api/#{WUNDERGROUND_API_KEYS}/conditions/geolookup/conditions/q/#{@state}/#{@city}.json")
    @temp_in_f = response["current_observation"]["temp_f"]

    @q =  profile["query"]
    search_response = HTTParty.get("http://api.nytimes.com/svc/search/v2/articlesearch.json?q=#{@q}&api-key=#{NYTIMES_ARTICLE_SEARCH_API_KEYS}")
    @search_parsed_response = JSON.parse search_response.to_json

    render(:erb, :show)
  end



  # gives back specific nytimes articles according to the search key word
  # get('/feed/:query') do
  #   @q = params["query"]
  #   binding.pry
  #   response = HTTParty.get("http://api.nytimes.com/svc/search/v2/articlesearch.json?q=#{@q}&api-key=#{NYTIMES_ARTICLE_SEARCH_API_KEYS}")
  #   @search_parsed_response = JSON.parse response.to_json
  #   render(:erb, :show)
  # end


  get('/twitter') do

    client = Twitter::REST::Client.new do |config|
      config.consumer_key         = TWITTER_API_KEYS
      config.consumer_secret      = TWITTER_API_SECRET
      config.access_token         = TWITTER_ACCESS_TOKEN
      config.access_token_secret  = TWITTER_ACCESS_TOKEN_SECRET
    end

    # topics = ["coffee", "tea"]
    # client.filter(:track => topics.join(",")) do |object|
    #   puts object.text if object.is_a?(Twitter::Tweet)
    # end
    binding.pry
    client.home_timeline
    # twitter_response = HTTParty.get("https://api.twitter.com/1.1/statuses/home_timeline.json")

  end

  post('/feed') do
    original_profile = JSON.parse $redis.get("profile:1")
    updated_profile = JSON.parse $redis.get("profile:1")

    updated_profile["query"] = params["query"]
    updated_profile["city"] = params["city"]
    updated_profile["state"] = params["state"]
    really_updated_profile = original_profile.merge(updated_profile) do |key, oldval, newval|
      if newval == nil
        oldval
      else
        newval
      end
    end
    $redis.set("profile:1", really_updated_profile.to_json)
    redirect to('/feed')
  end

  put('/profile/edit') do
    original_profile = JSON.parse $redis.get("profile:1")
    updated_profile = JSON.parse $redis.get("profile:1")
    updated_profile["name"] = params["name"]
    updated_profile["age"] = params["age"]
    updated_profile["location"] = params["location"]
    updated_profile["favorite ice-cream flavor"] = params["favorite ice-cream flavor"]
    updated_profile["nytimes_most_popular"] = params["nytimes_most_popular"]
    updated_profile["nytimes_article_search"] = params["nytimes_article_search"]
    updated_profile["local_weather"] = params["local_weather"]

    really_updated_profile = original_profile.merge(updated_profile) do |key, oldval, newval|
      if newval == ""
        oldval
      else
        newval
      end
    end

    $redis.set("profile:1", really_updated_profile.to_json)
    redirect to('/profile')
  end

  def get_model_from_redis(redis_id)
    model = JSON.parse($redis.get(redis_id))
    model
  end
end
  # get('/feed/:id') do
  #   # feed_id = params[:id]
  #   # if feed_id == "nytimes"
  #   article_response = HTTParty.get("http://api.nytimes.com/svc/mostpopular/v2/mostviewed/all-sections/1.json?api-key=#{NYTIMES_MOST_POPULAR_API_KEYS}")
  #   @parsed_response = JSON.parse article_response.to_json

  #   binding.pry
  #   render(:erb, :show)
  # end
