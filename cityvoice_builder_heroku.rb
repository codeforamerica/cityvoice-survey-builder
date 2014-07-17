require 'sinatra'

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
    puts params
    erb :show_params
  end
end
