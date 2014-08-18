require 'sinatra'
require 'httparty'
require 'json'
require 'redis'
require 'securerandom'

class CityvoiceBuilderHeroku < Sinatra::Base
  enable :sessions

  configure do
    set :redis, Redis.new(:host => ENV['REDISTOGO_URL'])
    # Usage:
    # redis.set("keyname", "value")
    # redis.get("keyname")
    # redis.expire("keyname", 100) # deletes keyname after 100 seconds
    # redis.ttl("keyname") # returns remaining seconds for life of keyname
  end

  get '/' do
    erb :index
  end

  post '/deployment/new' do
    user_token = SecureRandom.hex
    redirect to("/#{user_token}/locations")
  end

  get '/:user_token/locations' do
    @page_name = 'locations'
    erb :locations
  end

  post '/:user_token/locations' do
    redis = Redis.new(:host => ENV['REDISTOGO_URL'])
    key_for_locations = "#{params[:user_token]}_locations"
    redis.set(key_for_locations, params[:locations].to_json)
    redirect to("/#{params[:user_token]}/questions"), 303
    # For eventual location name-editing
    #redirect to('/locations/edit'), 303
  end

# No location name editing in v1, but backend work done here
=begin
  get '/locations/edit' do
    @page_name = 'locations'
    @locations = JSON.parse(session[:locations])
    erb :locations_edit
  end

  post '/locations/edit' do
    session[:locations] = params[:locations].to_json
    redirect to('/questions')
  end
=end

  get '/:user_token/questions' do
    @page_name = 'questions'
    erb :questions
  end

  post '/:user_token/questions' do
    redis = Redis.new(:host => ENV['REDISTOGO_URL'])
    key_for_questions = "#{params[:user_token]}_questions"
    redis.set(key_for_questions, params[:questions].to_json)
    redirect to("/#{params[:user_token]}/tarball"), 302
    # Do audio later
    #redirect to('/audio')
  end

# Do audio later
=begin
  get '/audio' do
    @page_name = 'audio'
    erb :audio
  end
=end

  get '/:user_token/tarball' do
    erb :tarball
  end

  post '/:user_token/tarball/build' do
  end

  get '/:user_token/push' do
    @page_name = 'push'
    erb :push
  end

  get '/create-app' do
    raise "Need to set HEROKU_OAUTH_ID" unless ENV.has_key?('HEROKU_OAUTH_ID')
    @heroku_authorize_url = "https://id.heroku.com/oauth/authorize?" \
      + "client_id=#{ENV['HEROKU_OAUTH_ID']}" \
      + "&response_type=code" \
      + "&scope=global" \
      + "&state="
    erb :push
  end

  get '/callback' do
    @token_exchange_response = HTTParty.post("https://id.heroku.com/oauth/token", \
      query: { \
        grant_type: "authorization_code", \
        code: params[:code], \
        client_secret: ENV['HEROKU_OAUTH_SECRET'] \
      })
    @app_build_response = HTTParty.post("https://api.heroku.com/app-setups", \
      headers: { \
        "Authorization" => "Bearer #{@token_exchange_response["access_token"]}", \
        "Accept" => "application/vnd.heroku+json; version=3", \
        "Content-Type" => "application/json" \
      }, \
      body: "{\"source_blob\": { \"url\": \"https://github.com/daguar/cityvoice/tarball/add-heroku-app-json-file\"}}")
    @built_app_url = "https://#{JSON.parse(@app_build_response.body)["app"]["name"]}.herokuapp.com"
    erb :response
  end
end
