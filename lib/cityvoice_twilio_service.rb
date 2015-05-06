class CityvoiceTwilioService

  def initialize(account_sid, auth_token)
    @client = Twilio::REST::Client.new(account_sid, auth_token)
  end

  def buy_number_by_locations(locations)
    #
    # Calculate average location.
    #
    lat, lng = 0, 0

    locations.each do |loc|
      lat += loc["lat"].to_f / locations.count
      lng += loc["lng"].to_f / locations.count
    end
    
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
    numbers = @client.available_phone_numbers.get('US').local.list(
      near_lat_long: sprintf( "%0.5f,%0.5f", lat, lng),
      distance: 50
    )
    
    wanted = numbers.first
    bought = @client.account.incoming_phone_numbers.create(:phone_number => wanted.phone_number)
    
    # Return a string like "(510) 555-1212"
    return bought
  end
end
