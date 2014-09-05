require 'json'
require 'httparty'
require 'pry'


  # WUNDERGROUND_API_KEYS = ENV['WUNDERGROUND_KEY'] #save as an environmental variable
  NYTIMES_MOST_POPULAR_API_KEYS = "85eb47a4b49d424d01237d5a8f3cd55b:18:62890239"

  response = HTTParty.get("http://api.nytimes.com/svc/mostpopular/v2/mostviewed/all-sections/1.json?api-key=#{NYTIMES_MOST_POPULAR_API_KEYS}")
  # binding.pry


  first_article_url = response["results"][0]["url"]
  first_article_title = response["results"][0]["title"]
  puts first_article_title
  puts first_article_url
