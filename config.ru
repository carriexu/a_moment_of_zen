require 'rubygems'
require 'bundler'

# require 'sinatra/base'
# require 'json'
# require 'redis'
# require 'httparty'
# require 'pry' if ENV["RACK_ENV"] == "development"
# require 'securerandom'
# require 'twitter'
# require 'uri'

Bundler.require(:default, ENV["RACK_ENV"].to_sym)

require './app'
run App
