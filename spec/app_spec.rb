require 'spec_helper'

describe CityvoiceBuilderHeroku do
  let(:user_token) { 'user_token' }

  it 'knows about a redis url' do
    expect(CityvoiceBuilderHeroku.settings).to respond_to(:redis_url)
  end

  context 'root page' do
    before do
      get 'https://example.dev/'
    end

    it 'responds successfully' do
      expect(last_response.status).to eq(200)
    end

    it 'has a button to get started with' do
      expect(last_response.body).to include('Get started')
    end
  end

  describe 'POST /deployment/new' do
    it 'generates a random token and redirects to /TOKEN/locations' do
      allow(SecureRandom).to receive(:hex).and_return('fakehextoken')
      post 'https://example.dev/deployment/new'
      expect(last_response).to be_redirect
      expect(last_response.location).to include('/fakehextoken/locations')
    end
  end

  describe 'GET /:user_token/locations' do
    it 'responds successfully' do
      get 'https://example.dev/fake_user_token/locations'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /:user_token/locations' do
    let(:locations_hash) { { "locations" => [{"name" => "155 9th St", "lat" => "lat1", "lng" => "lng1"}, {"name" => "200 Fell St", "lat" => "lat2", "lng" => "lng2"}] } }
    let(:locations_json) { locations_hash['locations'].to_json }
    let(:fake_redis) { double("FakeRedis", :set => 'var set') }
    let(:locations_key) { "#{user_token}_locations" }

    before do
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(CityvoiceBuilderHeroku.settings).to receive(:expiration_time).and_return(666)
    end

    it 'saves locations in redis' do
      expect(fake_redis).to receive(:set).with(locations_key, locations_json)
      expect(fake_redis).to receive(:expire).with(locations_key, 666)

      post "https://example.dev/#{user_token}/locations", locations_hash

      expect(last_response).to be_redirect
      expect(last_response.location).to include("/#{user_token}/questions")
    end
  end

  describe 'GET /:user_token/questions' do
    it 'responds successfully' do
      get 'https://example.dev/fake_user_token/questions'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /:user_token/questions' do
    let(:questions_hash) { { "questions" =>
          {
          "agree_questions" => [
            {
             "short_name" => "one",
             "question_text" => "one"
            },
            {
              "short_name" => "two",
              "question_text" => "two"
            }
          ],
          "voice_question_text" => "voice"
          } } }
    let(:fake_redis) { double('FakeRedis') }

    before do
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(CityvoiceBuilderHeroku.settings).to receive(:expiration_time).and_return(666)
    end

    it 'saves questions in redis for the user' do
      expect(fake_redis).to receive(:expire).with('user_token_questions', 666)
      expect(fake_redis).to receive(:set).with('user_token_questions', questions_hash['questions'].to_json)

      post 'https://example.dev/user_token/questions', questions_hash

      expect(last_response).to be_redirect
      expect(last_response.location).to eq('https://example.dev/user_token/audio/welcome')
    end
  end

  describe 'GET /:user_token/tarball' do
    before do
      get 'https://example.dev/fake_user_token/tarball'
    end

    it 'responds successfully' do
      pending 'this url path does not exist anymore'
      expect(last_response.status).to eq(200)
    end

    it 'has a button for building the tarball' do
      pending 'this url path does not exist anymore'
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
      get 'https://example.dev/fake_user_token/push'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /:user_token/push' do
    it 'responds successfully' do
      get 'https://example.dev/fake_user_token/push'
      expect(last_response.status).to eq(200)
    end
  end
end
