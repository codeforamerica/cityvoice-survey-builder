require 'sinatra'
require 'httparty'
require 'json'
require 'redis'
require 'securerandom'
require 'fileutils'
require 'twilio-ruby'
require 'sendgrid-ruby'
require File.expand_path('../lib/cityvoice_csv_generator', __FILE__)
require File.expand_path('../lib/cityvoice_twilio_service', __FILE__)

class CityvoiceBuilderHeroku < Sinatra::Base
  raise "Need to set HEROKU_OAUTH_ID" unless ENV.has_key?('HEROKU_OAUTH_ID')
  raise "Need to set HEROKU_OAUTH_SECRET" unless ENV.has_key?('HEROKU_OAUTH_SECRET')
  enable :sessions

  configure do
    set :force_ssl, true
    set :redis_url, URI.parse(ENV["REDISTOGO_URL"])
    set :expiration_time, 43200 # 12 hours ought to be enough for anybody
    # Usage:
    # redis.set("keyname", "value")
    # redis.get("keyname")
    # redis.expire("keyname", 100) # deletes keyname after 100 seconds
    # redis.ttl("keyname") # returns remaining seconds for life of keyname
    set :audio_info, {
      "welcome" => {
        "description" => "Use this message to give participants context for the purpose of the survey",
        "example" => "Hi, thanks for calling! Your feedback will help [INSERT SURVEY GOAL]."
      },
      "consent" => {
        "description" => "This message asks the caller if they’re open to being called back for follow-up discussion",
        "example" => "Would you like to make your phone number available for a follow-up to this survey? For yes, press 1. For no, press 2."
      },
      "fatal_error" => {
        "description" => "Just in case we have trouble hearing the caller, we’d like to include an error message recording. This message would be triggered if a caller makes an error several times in a row, ending the call.",
        "example" => "Sorry! We're having trouble recording your input. If you'd like a different way to contact us [INSERT ALTERNATE WAY TO CONTACT YOU]."
      },
      "thanks" => {
        "description" => "Use this message to thank the caller and tell them why their participation matters",
        "example" => "Thanks! Your feedback will help us [GOAL]. If you would like to get involved in [SURVEY TOPIC], please [MORE CONTACT INFO]."
      },
    }
  end

  before do
    if settings.force_ssl && !request.secure?
      redirect to("https://#{request.host}#{request.path}?#{request.query_string}")
    end
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
  end

  get '/:user_token/questions' do
    @page_name = 'questions'
    erb :questions
  end

  post '/:user_token/questions' do
    clean_questions = Hash.new
    clean_questions["agree_questions"] = params[:questions]["agree_questions"].select do |q|
      q["short_name"] != ""
    end.each do |q|
      q["short_name"] = q["short_name"].gsub(" ", "_").gsub(/\W/, "")
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
    @current_audio_name = params[:current_audio_name].gsub("-", " ")
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
      next_audio_name = audio_names[current_audio_index + 1].gsub(" ","-")
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

    #
    # After locations, questions, and audio, but before
    # pushing build to Heroku, add phone number selection.
    #
    # Use average lat/lon and IncomingPhoneNumbers to find local numbers,
    # and display a list for people to choose from. They may have feelings
    # about the right area code to use:
    #
    #   https://github.com/codeforamerica/cityvoice-survey-builder/issues/61#issuecomment-97584397
    #
    # After user selects a phone number, reserve it with Twilio:
    #
    #   https://github.com/codeforamerica/cityvoice-survey-builder/issues/61#issuecomment-97588226
    #
    # Include the phone number in the tarball, if Dave is to be believed.
    #
    locations = JSON.parse(redis.get("#{params[:user_token]}_locations"))
    questions = JSON.parse(redis.get("#{params[:user_token]}_questions"))
    twilio_sid, twilio_token = ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']
    number = CityvoiceTwilioService.new(twilio_sid, twilio_token)
                                   .buy_number_by_locations(locations)
    redis.set("#{params[:user_token]}_number_sid", number.sid)
    redis.set("#{params[:user_token]}_number_friendly_name", number.friendly_name)
    app_content_set_csv_string = CityvoiceCsvGenerator.app_content_set_csv(number.friendly_name)
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
    app_content_set_csv_path = "#{path_to_repo}/data/app_content_set.csv"
    locations_csv_path = "#{path_to_repo}/data/locations.csv"
    questions_csv_path = "#{path_to_repo}/data/questions.csv"
    File.delete(app_content_set_csv_path)
    File.delete(locations_csv_path)
    File.delete(questions_csv_path)
    # Write new CSV files in tmp folder
    File.open(app_content_set_csv_path, 'w') do |file|
      file.write(app_content_set_csv_string)
    end
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
    
    #
    # After Heroku authorization add phone number configuration
    # and email to CfA about new signups.
    #
    # Use the generated app name to create a voice callback URL and inform Twilio:
    #
    #   https://github.com/codeforamerica/cityvoice-survey-builder/issues/61#issuecomment-97589478
    #
    redis = Redis.new(:url => settings.redis_url)
    number_sid = redis.get("#{params[:state]}_number_sid")
    voice_url = "#{@built_app_url}/calls"
    twilio_sid, twilio_token = ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']

    CityvoiceTwilioService.new(twilio_sid, twilio_token)
                               .set_number_voice_url(number_sid, voice_url)
    
    #
    # Use Heroku account information to inform CfA:
    #
    #   https://github.com/codeforamerica/cityvoice-survey-builder/issues/61#issuecomment-97606058
    #
    @account_info_response = HTTParty.get("https://api.heroku.com/account", \
      headers: { \
        "Authorization" => "Bearer #{@token_exchange_response["access_token"]}", \
        "Accept" => "application/vnd.heroku+json; version=3" \
      })
    parsed_account_response = JSON.parse(@account_info_response.body)

    if ENV.has_key?('SENDGRID_USERNAME') && ENV.has_key?('SENDGRID_PASSWORD')
      client = SendGrid::Client.new(api_user: ENV['SENDGRID_USERNAME'], api_key: ENV['SENDGRID_PASSWORD'])
      mail = SendGrid::Mail.new(
        to: 'cityvoice-support@codeforamerica.org',
        cc: 'mike@codeforamerica.org',
        from: 'mike@codeforamerica.org',
        subject: 'CityVoice got used',
        text: <<-EOF
          #{parsed_account_response['email']} at #{@built_app_url}
          EOF
      )
    
      puts client.send(mail)
    end
    
    redis.set("#{params[:state]}_built_app_url", @built_app_url)
    redirect to("/#{params[:state]}/finished"), 302
  end

  get '/:user_token/finished' do
  
    redis = Redis.new(:url => settings.redis_url)
    @built_app_url = redis.get("#{params[:user_token]}_built_app_url")
    @phone_number = redis.get("#{params[:user_token]}_number_friendly_name")
  
    erb :response
  end

  get '/sign' do
    puts params
    if params.empty?
      erb :sign_form
    else
      @args = params
      @contact_info_with_html_line_breaks = params["contact-info"].gsub("\n", "<br>")
      erb :sign_template, layout: false
    end
  end
end
