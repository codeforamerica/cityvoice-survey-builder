require 'sinatra'
require 'httparty'
require 'json'

class CityvoiceBuilderHeroku < Sinatra::Base
  get '/' do
    raise "Need to set HEROKU_OAUTH_ID" unless ENV.has_key?('HEROKU_OAUTH_ID')
    @heroku_authorize_url = "https://id.heroku.com/oauth/authorize?" \
      + "client_id=#{ENV['HEROKU_OAUTH_ID']}" \
      + "&response_type=code" \
      + "&scope=global" \
      + "&state="
    erb :index
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
