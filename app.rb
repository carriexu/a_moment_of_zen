require 'sinatra/base'
require 'json'
require 'redis'
require 'httparty'
require 'pry' if ENV["RACK_ENV"] == "development"
require 'securerandom'
require 'twitter'
require 'uri'

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

  NYTIMES_MOST_POPULAR_API_KEYS = ENV["NYTIMES_MOST_POPULAR_API_KEYS"]
  NYTIMES_ARTICLE_SEARCH_API_KEYS = ENV["NYTIMES_ARTICLE_SEARCH_API_KEYS"]
  TWITTER_API_KEYS = ENV["TWITTER_API_KEY"]
  TWITTER_API_SECRET = ENV["TWITTER_API_SECRET"]
  TWITTER_ACCESS_TOKEN = ENV["TWITTER_ACCESS_TOKEN"]
  TWITTER_ACCESS_TOKEN_SECRET = ENV["TWITTER_ACCESS_TOKEN_SECRET"]
  # could not get below twitter username to work
  # TWITTER_USERNAME = "carrielovesfood"
  WUNDERGROUND_API_KEYS = ENV["WUNDERGROUND_API_KEYS"]
  INSTAGRAM_CLIENT_ID = ENV["INSTAGRAM_CLIENT_ID"]
  INSTAGRAM_CLIENT_SECRET = ENV["INSTAGRAM_CLIENT_SECRET"]
  # INSTAGRAM_REDIRECT_URL = "http://127.0.0.1:9292/oauth_callback/instagram"
  INSTAGRAM_REDIRECT_URL = "http://infinite-spire-5264.herokuapp.com/oauth_callback/instagram"

  FACEBOOK_CLIENT_ID = ENV["FACEBOOK_CLIENT_ID"]
  FACEBOOK_CLIENT_SECRET = ENV["FACEBOOK_CLIENT_SECRET"]
  # FACEBOOK_REDIRECT_URL = "http://127.0.0.1:9292/oauth_callback/facebook"
  FACEBOOK_REDIRECT_URL = "http://infinite-spire-5264.herokuapp.com/oauth_callback/facebook"


  ########################
  # Routes
  ########################

  get('/') do
    # Instagram OAuth
    instagram_base_url = "https://api.instagram.com/oauth/authorize"
    instagram_scope = "user"
    instagram_state = SecureRandom.urlsafe_base64

    facebook_base_url = "https://www.facebook.com/dialog/oauth"
    facebook_scope = "public_profile"
    facebook_state = SecureRandom.urlsafe_base64
    # storing state in session because we need to compare it in a later request
    # the following does not work, cannot set session[:state] to both instagram_state and facebook_state
    session[:instagram_state] = instagram_state
    session[:facebook_state] = facebook_state

    @instagram_uri = "#{instagram_base_url}?client_id=#{INSTAGRAM_CLIENT_ID}&redirect_uri=#{INSTAGRAM_REDIRECT_URL}&response_type=code&state=#{instagram_state}"
    @facebook_uri = "#{facebook_base_url}?client_id=#{FACEBOOK_CLIENT_ID}&redirect_uri=#{FACEBOOK_REDIRECT_URL}&response_type=code&state=#{facebook_state}"
    render(:erb, :index)
  end

  get('/oauth_callback/instagram') do
    # Instagram OAuth
    # puts session
    # state = params[:state]
    code = params[:code]
    # compare the states to ensure the information is from who we think it is
    if session[:instagram_state] == params[:state]
      instagram_response = HTTParty.post("https://api.instagram.com/oauth/access_token",
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
        session[:instagram_access_token] = instagram_response["access_token"]
    end
    redirect to("/feed")
  end

  get('/oauth_callback/facebook') do
    code = params[:code]

    if session[:facebook_state] == params[:state]
      facebook_response = HTTParty.post("https://graph.facebook.com/oauth/access_token",
                              :body => {
                                client_id: FACEBOOK_CLIENT_ID,
                                redirect_uri: FACEBOOK_REDIRECT_URL,
                                client_secret: FACEBOOK_CLIENT_SECRET,
                                code: code
                              },
                              :headers =>{
                                  "Accept" => "application/json"
                                  })
      # a hack to get the access code
      # session[:access_token] = facebook_response["access_token"]
        session[:facebook_access_token] = facebook_response.to_s.split("&")[0].split("=")[1]
    end
    redirect to("/feed")
  end

  get('/logout/instagram') do
    session[:instagram_access_token] = nil
    redirect to('/')
  end

  get('/logout/facebook') do
    session[:facebook_access_token] = nil
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
    @profile = JSON.parse $redis.get("profile:1")
    # NYTIMES Most Popular Stories
    response = HTTParty.get("http://api.nytimes.com/svc/mostpopular/v2/mostviewed/all-sections/1.json?api-key=#{NYTIMES_MOST_POPULAR_API_KEYS}&offset=20")
    @parsed_response = JSON.parse response.to_json

    # your weather
    @city = @profile["city"].gsub(" ", "%20")
    @state = @profile["state"].gsub(" ", "%20")
    response = HTTParty.get("http://api.wunderground.com/api/#{WUNDERGROUND_API_KEYS}/conditions/geolookup/conditions/q/#{@state}/#{@city}.json")
    @temp_in_f = response["current_observation"]["temp_f"]
    # NYTIMES Search Articles
    @q =  @profile["query"]
    search_response = HTTParty.get("http://api.nytimes.com/svc/search/v2/articlesearch.json?q=#{@q}&api-key=#{NYTIMES_ARTICLE_SEARCH_API_KEYS}")
    @search_parsed_response = JSON.parse search_response.to_json
    # Configure Twitter
    client = Twitter::REST::Client.new do |config|
      config.consumer_key         = TWITTER_API_KEYS
      config.consumer_secret      = TWITTER_API_SECRET
      config.access_token         = TWITTER_ACCESS_TOKEN
      config.access_token_secret  = TWITTER_ACCESS_TOKEN_SECRET
    end
    # Twitter My Timeline
    my_timeline = client.user_timeline("carrielovesfood")
    @my_tweets = []
    my_timeline.each do |tweet|
      tweet_text = tweet.text
      @my_tweets << tweet_text
    end
    # Twitter Search Results display 5
    @twitter_search_result = client.search("#{@q}", :result_type => "recent").take(5).collect do |tweet|
      "#{tweet.user.screen_name}: #{tweet.text}"
    end


    # Instagram My feed
    insta_access_token = session[:instagram_access_token]
    response = HTTParty.get("https://api.instagram.com/v1/users/self/feed?access_token=#{insta_access_token}")
    @insta_response = JSON.parse response.to_json
    # Instagram Searched by Tag Feed
    # binding.pry

    response = HTTParty.get("https://api.instagram.com/v1/tags/#{@q}/media/recent?access_token=#{insta_access_token}")
    @insta_searched_response = JSON.parse response.to_json
    render(:erb, :show)
    # Instagram Searched by Location Feed
    # https://api.instagram.com/v1/locations/514276/media/recent?access_token=ACCESS-TOKEN
    # Facebook
    # binding.pry
    # # response = HTTParty.get("http://graph.facebook.com/endpoint?key=value&access_token=app_id|app_secret")
    # response = HTTParty.get("http://graph.facebook.com/me")

  end

  # get('/feed/:feed_id') do
  #   @profile = JSON.parse $redis.get("profile:1")
  # end
  # updates the location and search keyword
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
  # edits profile information and send to redis db
  put('/profile/edit') do
    original_profile = JSON.parse $redis.get("profile:1")
    updated_profile = JSON.parse $redis.get("profile:1")
    updated_profile["name"] = params["name"]
    updated_profile["age"] = params["age"]
    updated_profile["city"] = params["city"]
    updated_profile["state"] = params["state"]
    updated_profile["favorite ice-cream flavor"] = params["favorite ice-cream flavor"]
    updated_profile["nytimes_most_popular"] = params["nytimes_most_popular"]
    updated_profile["nytimes_article_search"] = params["nytimes_article_search"]
    updated_profile["local_weather"] = params["local_weather"]
    updated_profile["twitter_my_timeline"] = params["twitter_my_timeline"]
    updated_profile["twitter_search_result"] = params["twitter_search_result"]
    updated_profile["instagram_my_feed"] = params["instagram_my_feed"]
    updated_profile["instagram_searched_feed"] = params["instagram_searched_feed"]

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

