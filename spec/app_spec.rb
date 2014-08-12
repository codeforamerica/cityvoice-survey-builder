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
end
