require 'spec_helper'

describe CityvoiceCsvGenerator do
  describe '::locations_csv' do
    let(:locations_array) { [{"name" => "155 9th St", "lat" => "lat1", "lng" => "lng1"}, {"name" => "200 Fell St", "lat" => "lat2", "lng" => "lng2"}] }

    it 'creates a CSV string in CityVoice format' do
      new_csv = CityvoiceCsvGenerator.locations_csv(locations_array)
      desired_csv_string = <<EOF
Name,Lat,Long
155 9th St,lat1,lng1
200 Fell St,lat2,lng2
EOF
      expect(new_csv).to eq(desired_csv_string)
    end
  end
end
