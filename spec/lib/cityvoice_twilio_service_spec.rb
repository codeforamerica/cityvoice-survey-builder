require 'spec_helper'

describe CityvoiceTwilioService do
  let(:fake_client) { double('Twilio::REST::Client') }
  let(:fake_number) { double('number', :friendly_name => '(222) 333-4444', :phone_number => '+12223334444', :sid => '0xDEADBEEF') }
  let(:fake_local_resource) { double('local', :list => [fake_number]) }
  let(:fake_incoming_number_resource) { double('incoming_numbers', :create => fake_number) }

  before do
    allow(Twilio::REST::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive_message_chain(:available_phone_numbers, :get, :local)
      .and_return(fake_local_resource)
    allow(fake_client).to receive_message_chain(:account, :incoming_phone_numbers)
      .and_return(fake_incoming_number_resource)
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
        @result = CityvoiceTwilioService.new("sid","token").buy_number_by_locations(location_input)
      end

      it 'sends the average of locations to the Twilio client' do
        expect(fake_local_resource).to have_received(:list).with(
          near_lat_long: "37.80550,-122.26785",
          distance: 50
        )
      end

      it 'purchases the first available number' do
        expect(fake_incoming_number_resource).to have_received(:create).with(phone_number: fake_number.phone_number)
      end

      it 'should get a nearby phone number for some location' do
        expect(@result).to eq(fake_number)
      end
    end
  end
end
