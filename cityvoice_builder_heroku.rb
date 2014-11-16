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
    set :audio_info, {
      "welcome" => {
        "description" => "The first message played to a caller, giving context for the survey",
        "example" => "Hi, thanks for calling! Your feedback will help us [GOAL]."
      },
      "consent" => {
        "description" => "Asks the caller for consent to be called back",
        "example" => "Do you want to make your phone number available for follow-up to this survey? For yes, press 1. For no, press 2."
      },
      "fatal_error" => {
        "description" => "An error message played when the user has made an error multiple times (ending the call)",
        "example" => "Sorry! We're having problems understanding your input. If you'd like to contact us and leave a voicemail, please call [PHONE NUMBER]."
      },
      "thanks" => {
        "description" => "The final message played, after the survey is done",
        "example" => "Thanks! Your feedback will help us [GOAL]. If you would like to get involved in [SURVEY TOPIC], please [MORE CONTACT INFO]."
      },
    }
  end

  get '/' do
    erb :index
  end

  get '/signup' do
    @page_name = 'signup'
    erb :signup
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
    #redirect to("/#{params[:user_token]}/tarball/build"), 303
    redirect to("/#{params[:user_token]}/audio/welcome"), 303
  end

  get '/:user_token/audio/:current_audio_name' do
    @page_name = 'audio'
    @user_token = params[:user_token]
    redis = Redis.new(:url => settings.redis_url)
    questions = JSON.parse(redis.get("#{params[:user_token]}_questions"))
    question_short_names = Array.new
    question_short_names += questions["agree_questions"].map { |q| q["short_name"] }
    question_short_names += ['voice_question']
    audio_names = %w(welcome consent)
    audio_names += question_short_names
    audio_names += %w(fatal_error thanks)
    @current_audio_name = params[:current_audio_name]
    if settings.audio_info.has_key?(@current_audio_name)
      @current_audio_description = settings.audio_info[@current_audio_name]["description"]
      @current_audio_example = settings.audio_info[@current_audio_name]["example"]
    elsif @current_audio_name == 'voice_question'
      @current_audio_description = "Here, record the open-ended voice question you wrote before"
      @current_audio_example = questions['voice_question_text'] + " You will have 30 seconds to record your comments."
    else
      # Agree/disagree questions
      @current_audio_description = "This is your agree/disagree question '#{@current_audio_name}'"
      question = questions["agree_questions"].select { |q| q["short_name"] == @current_audio_name }.first
      @current_audio_example = question["question_text"] + " . Press 1 if you agree or press 2 if you disagree."
    end
    current_audio_index = audio_names.index(@current_audio_name)
    if @current_audio_name == "thanks"
      @next_link = "/#{@user_token}/tarball/build"
    else
      next_audio_name = audio_names[current_audio_index + 1]
      @next_link = "/#{@user_token}/audio/#{next_audio_name}"
    end
    erb :audio
  end

  post '/:user_token/audio/:current_audio_name' do
    audio_name = params[:current_audio_name]
    user_token = params[:user_token]
    wav_path = params["data"][:tempfile].path
    mp3_path = "/tmp/#{user_token}_audio_#{audio_name}.mp3"
    # Convert wav to mp3
    system("lame -V 2 #{wav_path} #{mp3_path}")
    # Read mp3 as binary and put in Redis
    raw_mp3_binary_data = IO.binread(mp3_path)
    redis = Redis.new(:url => settings.redis_url)
    redis_key = "#{user_token}_audio_#{audio_name}"
    redis.set(redis_key, raw_mp3_binary_data)
    redis.expire(redis_key, settings.expiration_time)
    puts "Redis key: #{redis_key}"
    return "blob saved!"
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

  get '/:user_token/tarball/build' do
    token = params[:user_token]
    redis = Redis.new(:url => settings.redis_url)
    # Get JSON data out of Redis
    # Parse JSON from Redis into Ruby hashes
    locations = JSON.parse(redis.get("#{params[:user_token]}_locations"))
    questions = JSON.parse(redis.get("#{params[:user_token]}_questions"))
    locations_csv_string = CityvoiceCsvGenerator.locations_csv(locations)
    questions_csv_string = CityvoiceCsvGenerator.questions_csv(questions)
    # Download latest CityVoice Tarball from GitHub to /tmp
    source_tarball = HTTParty.get("http://github.com/codeforamerica/cityvoice/tarball/master")
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
    ### Audio
    question_short_names = Array.new
    question_short_names += questions["agree_questions"].map { |q| q["short_name"] }
    question_short_names += ['voice_question']
    audio_file_names = %w(welcome consent)
    audio_file_names += question_short_names
    audio_file_names += %w(fatal_error thanks)
    audio_file_names.each do |audio_name|
      # Delete audio
      audio_path = "#{path_to_repo}/app/assets/audios/#{audio_name}.mp3"
      if File.exist?(audio_path)
        FileUtils.rm_rf(audio_path)
      end
      # Take out binary from redis for audio
      binary = redis.get("#{params[:user_token]}_audio_#{audio_name}")
      # Write new mp3 audio to file
      File.open(audio_path, 'wb') do |file|
        file.write(binary)
      end
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
        "Accept" => "application/vnd.heroku+json; version=edge", \
        "Content-Type" => "application/json" \
      }, \
      body: "{\"source_blob\": { \"url\": \"#{tarball_url}\"}, \"app\": { \"stack\": \"cedar\" } }")
    parsed_response = JSON.parse(@app_build_response.body)
    @built_app_url = nil
    if parsed_response["app"]
      if parsed_response["app"]["name"]
        @built_app_url = "https://#{parsed_response["app"]["name"]}.herokuapp.com"
      end
    end
    erb :response
  end
end
