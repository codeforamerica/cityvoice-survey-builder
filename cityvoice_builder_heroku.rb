require 'sinatra'
require 'httparty'
require 'json'

class CityvoiceBuilderHeroku < Sinatra::Base
  enable :sessions

  get '/' do
    erb :index
  end

  get '/create-app' do
    raise "Need to set HEROKU_OAUTH_ID" unless ENV.has_key?('HEROKU_OAUTH_ID')
    @heroku_authorize_url = "https://id.heroku.com/oauth/authorize?" \
      + "client_id=#{ENV['HEROKU_OAUTH_ID']}" \
      + "&response_type=code" \
      + "&scope=global" \
      + "&state="
    erb :index
  end

  get '/locations' do
    @page_name = 'locations'
    erb :locations
  end

  post '/locations' do
    puts params
    session[:locations] = params[:locations].to_json
    redirect to('/locations/edit'), 303
  end

  get '/locations/edit' do
    @page_name = 'locations'
    @locations = JSON.parse(session[:locations])
    erb :locations_edit
  end

  get '/questions' do
    @page_name = 'questions'
    erb :questions
  end

  post '/questions' do
    puts params
    redirect to('/audio')
  end

  get '/audio' do
    @page_name = 'audio'
    erb :audio
  end

  get '/push' do
    @page_name = 'push'
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
