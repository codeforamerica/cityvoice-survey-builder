require 'spec_helper'

describe CityvoiceBuilderHeroku do
  let(:user_token) { 'myusertoken' }

  it 'has a redis connection' do
    expect(CityvoiceBuilderHeroku.settings.redis).to be_a(Redis)
  end

  context 'root page' do
    before(:each) do
      get '/'
    end

    it 'responds successfully' do
      expect(last_response.status).to eq(200)
    end

    it 'has a button with POST to creating a new user key' do
      expect(last_response.body).to include('action="/deployment/new" method="post"')
    end
  end

  describe 'POST /deployment/new' do
    it 'generates a random token and redirects to /TOKEN/locations' do
      allow(SecureRandom).to receive(:hex).and_return('fakehextoken')
      post '/deployment/new'
      expect(last_response).to be_redirect
      expect(last_response.location).to include('/fakehextoken/locations')
    end
  end

  describe 'GET /:user_token/locations' do
    it 'responds successfully' do
      get '/fake_user_token/locations'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /:user_token/locations' do
    let(:locations_hash) { { "locations" => [{"name" => "155 9th St", "lat" => "lat1", "lng" => "lng1"}, {"name" => "200 Fell St", "lat" => "lat2", "lng" => "lng2"}] } }
    let(:fake_redis) { double("FakeRedis", :set => 'var set') }

    before do
      allow(Redis).to receive(:new).and_return(fake_redis)
      post "/#{user_token}/locations", locations_hash
    end

    it 'saves locations in redis for the user' do
      expect(fake_redis).to have_received(:set).with("#{user_token}_locations", locations_hash["locations"].to_json)
    end

    it 'redirects to /:user_token/questions' do
      expect(last_response).to be_redirect
      expect(last_response.location).to include("/#{user_token}/questions")
    end
  end

  describe 'GET /:user_token/questions' do
    it 'responds successfully' do
      get '/fake_user_token/questions'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /:user_token/questions' do
    let(:questions_hash) { { "questions" => { "agree_questions" => [{"short_name" => "Property Outcome", "question_text" => "Should this property be demolished?"}, {"short_name" => "Property Condition", "question_text" => "Is this property in good condition?"}], "voice_question_text" => "What else do you think about this property?" } } }
    let(:fake_redis) { double("FakeRedis", :set => 'var set') }

    before do
      allow(Redis).to receive(:new).and_return(fake_redis)
      post "/#{user_token}/questions", questions_hash
    end

    it 'saves questions in redis for the user' do
      expect(fake_redis).to have_received(:set).with("#{user_token}_questions", questions_hash["questions"].to_json)
    end

    it 'redirects to /:user_token/push' do
      expect(last_response).to be_redirect
      expect(last_response.location).to include("/#{user_token}/tarball")
    end
  end

  describe 'GET /:user_token/tarball' do
    before do
      get '/fake_user_token/tarball'
    end

    it 'responds successfully' do
      expect(last_response.status).to eq(200)
    end

    it 'has a button for building the tarball' do
      button_snippet = "action=\"/fake_user_token/tarball/build\" method=\"post\""
      expect(last_response.body).to include(button_snippet)
    end
  end

  describe 'POST /:user_token/tarball/build' do
    let(:fake_redis) { double("Redis") }
    let(:locations_json) { { "locations" => [{"name" => "155 9th St", "lat" => "lat1", "lng" => "lng1"}, {"name" => "200 Fell St", "lat" => "lat2", "lng" => "lng2"}] }.to_json }
    let(:questions_json) { { "questions" => { "agree_questions" => [{"short_name" => "Property Outcome", "question_text" => "Should this property be demolished?"}, {"short_name" => "Property Condition", "question_text" => "Is this property in good condition?"}], "voice_question_text" => "What else do you think about this property?" } }.to_json }

    before do
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(fake_redis).to receive(:get).with("fake_user_token_locations").and_return(locations_json)
      allow(fake_redis).to receive(:get).with("fake_user_token_questions").and_return(questions_json)
      post '/fake_user_token/tarball/build'
    end

#    it 'responds successfully' do
#      expect(last_response.status).to eq(200)
#    end

#    it 'pulls data from redis' do
#      expect(fake_redis).to have_received(:get).with("fake_user_token_locations").once
#      expect(fake_redis).to have_received(:get).with("fake_user_token_questions").once
#    end
  end

  describe 'GET /:user_token/push' do
    it 'responds successfully' do
      get '/fake_user_token/push'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /:user_token/push' do
    it 'responds successfully' do
      get '/fake_user_token/push'
      expect(last_response.status).to eq(200)
    end
  end
end
