require 'sinatra'
require 'httparty'
require 'json'
require 'redis'
require 'securerandom'
require 'fileutils'
require File.expand_path('../lib/cityvoice_csv_generator', __FILE__)

class CityvoiceBuilderHeroku < Sinatra::Base
  raise "Need to set HEROKU_OAUTH_ID" unless ENV.has_key?('HEROKU_OAUTH_ID')
  raise "Need to set HEROKU_OAUTH_SECRET" unless ENV.has_key?('HEROKU_OAUTH_SECRET')
  enable :sessions

  configure do
    set :redis_url, URI.parse(ENV["REDISTOGO_URL"])
    set :expiration_time, 600
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
    redis = Redis.new(:url => settings.redis_url)
    key_for_locations = "#{params[:user_token]}_locations"
    redis.set(key_for_locations, params[:locations].to_json)
    redis.expire(key_for_locations, settings.expiration_time)
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
    clean_questions = Hash.new
    clean_questions["agree_questions"] = params[:questions]["agree_questions"].select do |q|
      q["short_name"] != ""
    end
    clean_questions["voice_question_text"] = params[:questions]["voice_question_text"]
    redis = Redis.new(:url => settings.redis_url)
    key_for_questions = "#{params[:user_token]}_questions"
    redis.set(key_for_questions, clean_questions.to_json)
    redis.expire(key_for_questions, settings.expiration_time)
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

  get '/:user_token/tarball/download' do
    redis = Redis.new(:url => settings.redis_url)
    binary = redis.get("#{params[:user_token]}_tarball")
    tarball_path = "/tmp/tmp_custom_tarball_#{params[:user_token]}.tar.gz"
    FileUtils.rm_rf(tarball_path)
    File.open(tarball_path, 'wb') do |file|
      file.write(binary)
    end
    send_file(tarball_path, :filename => "cityvoice_custom_tarball_#{params[:user_token]}.tar.gz")
  end

  post '/:user_token/tarball/build' do
    token = params[:user_token]
    redis = Redis.new(:url => settings.redis_url)
    # Get JSON data out of Redis
    # Parse JSON from Redis into Ruby hashes
    locations = JSON.parse(redis.get("#{params[:user_token]}_locations"))
    questions = JSON.parse(redis.get("#{params[:user_token]}_questions"))
    locations_csv_string = CityvoiceCsvGenerator.locations_csv(locations)
    questions_csv_string = CityvoiceCsvGenerator.questions_csv(questions)
    # Download latest CityVoice Tarball from GitHub to /tmp
    source_tarball = HTTParty.get("http://github.com/daguar/cityvoice/tarball/dont-raise-without-secret-token")
    tarball_path = "/tmp/cityvoice_source_from_github_#{token}.tar.gz"
    FileUtils.rm_rf(tarball_path)
    File.open(tarball_path, "w") do |file|
      file.write(source_tarball)
    end
    # Extract tarball to folder in tmp
    destination_path = "/tmp/cityvoice_source_decompressed_#{token}"
    FileUtils.rm_rf(destination_path)
    FileUtils.mkdir(destination_path)
    system("tar -zxvf #{tarball_path} -C #{destination_path}")
    path_to_repo = Dir[destination_path + "/*"][0]
    # Delete CSV files in tmp folder
    locations_csv_path = "#{path_to_repo}/data/locations.csv"
    questions_csv_path = "#{path_to_repo}/data/questions.csv"
    File.delete(locations_csv_path)
    File.delete(questions_csv_path)
    # Write new CSV files in tmp folder
    File.open(locations_csv_path, 'w') do |file|
      file.write(locations_csv_string)
    end
    File.open(questions_csv_path, 'w') do |file|
      file.write(questions_csv_string)
    end
    # Create tarball of tmp folder
    custom_tarball_path = "/tmp/cityvoice_custom_tarball_#{token}.tar.gz"
    system("tar -C #{path_to_repo} -pczf #{custom_tarball_path} .")
    # Store tarball in Redis
    raw_custom_tarball_binary = IO.binread(custom_tarball_path)
    redis.set("#{token}_tarball", raw_custom_tarball_binary)
    redis.expire("#{token}_tarball", settings.expiration_time)
    redirect to("/#{params[:user_token]}/push"), 302
  end

  get '/:user_token/push' do
    @heroku_authorize_url = "https://id.heroku.com/oauth/authorize?" \
      + "client_id=#{ENV['HEROKU_OAUTH_ID']}" \
      + "&response_type=code" \
      + "&scope=global" \
      + "&state=#{params[:user_token]}"
    @page_name = 'push'
    erb :push
  end

  get '/callback' do
    tarball_url = "https://#{request.env['HTTP_HOST']}/#{params[:state]}/tarball/download"
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
      body: "{\"source_blob\": { \"url\": \"#{tarball_url}\"}}")
    #@built_app_url = "https://#{JSON.parse(@app_build_response.body)["app"]["name"]}.herokuapp.com"
    erb :response
  end
end
