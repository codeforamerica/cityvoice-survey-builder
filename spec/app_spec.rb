require 'spec_helper'

describe CityvoiceBuilderHeroku do
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
    let(:fake_redis) { double("FakeRedis", :set => 'var set') }
    let(:user_token) { 'myusertoken' }
    let(:locations_hash) { { :locations => [{"name" => "155 9th St", "lat" => "lat1", "lng" => "lng1"}, {"name" => "200 Fell St", "lat" => "lat2", "lng" => "lng2"}] } }

    it 'saves locations in redis for the user' do
      allow(Redis).to receive(:new).and_return(fake_redis)
      post "/#{user_token}/locations", locations_hash
      expect(fake_redis).to have_received(:set).with("#{user_token}_locations", locations_hash[:locations].to_json)
    end
  end
end
