require 'spec_helper'

describe CityvoiceBuilderHeroku do
  it 'responds at root' do
    get '/'
    expect(last_response.status).to eq(200)
  end
end
