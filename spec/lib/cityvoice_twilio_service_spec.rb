require 'spec_helper'

describe CityvoiceTwilioService do
  let(:fake_client) { double('Twilio::REST::Client') }

  before do
    allow(Twilio::REST::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive_chain(:available_phone_numbers, :get, :local, :list)
  end
  
  describe '#buy_number_by_location' do
    context 'a set of locations with either float or string values' do    
      let(:location_input) {
        [
          { 'lat' => 37.8129, 'lng' => -122.2742 },
          { 'lat' => '37.7981', 'lng' => '-122.2615' }
        ]
      }
      
      before do
        result = CityvoiceTwilioService.new("sid","token").buy_number_by_locations(location_input)
      end
    
      it 'sends the average of locations to the Twilio client' do
        expect(fake_client).to receive_chain('available_phone_numbers.get.local.list').with(
          near_lat_long: "37.8055,-122.26785",
          distance: 50
        )
      end
      
      pending
      it 'should get a nearby phone number for some location' do
      end
    end
  end
end