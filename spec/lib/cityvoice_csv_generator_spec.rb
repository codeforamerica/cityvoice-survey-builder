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

  describe '::questions_csv' do
    let(:questions_hash) { { "agree_questions" => [{"short_name" => "Property Outcome", "question_text" => "Should this property be demolished?"}, {"short_name" => "Property Condition", "question_text" => "Is this property in good condition?"}], "voice_question_text" => "What else do you think about this property?" } }

    it 'creates a CSV string in CityVoice format' do
      new_csv = CityvoiceCsvGenerator.questions_csv(questions_hash)
      desired_csv_string = <<EOF
Short Name,Feedback Type,Question Text
Property Outcome,numerical_response,Should this property be demolished?
Property Condition,numerical_response,Is this property in good condition?
Voice Question,voice_file,What else do you think about this property?
EOF
      expect(new_csv).to eq(desired_csv_string)
    end
  end

  describe '::app_content_set_csv' do
    let(:phone_number) { "(510) 555-1212" }

    it 'creates a CSV string in CityVoice format' do
      new_csv = CityvoiceCsvGenerator.app_content_set_csv(phone_number)
      desired_csv_string = <<EOF
Issue,App Phone Number,Message From,Message URL,Header Color,Short Title,Call In Code Digits,Feedback Form URL
CityVoice,#{phone_number},CityVoice Maintainers,/assets/welcome.mp3,#6DC6AD,CityVoice,3,http://example.com
EOF
      expect(new_csv).to eq(desired_csv_string)
    end
  end
end
