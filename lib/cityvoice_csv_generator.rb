module CityvoiceCsvGenerator
  def self.locations_csv(locations)
    csv_string = CSV.generate do |csv|
      csv << %w(Name Lat Long)
      locations.each do |loc|
        csv << [loc["name"], loc["lat"], loc["lng"]]
      end
    end
    csv_string
  end

  def self.questions_csv(questions)
    csv_string = CSV.generate do |csv|
      csv << ["Short Name", "Feedback Type", "Question Text"]
      questions["agree_questions"].each do |q|
        csv << [q["short_name"], "numerical_response", q["question_text"]]
      end
      csv << ["voice_question", "voice_file", questions["voice_question_text"]]
    end
    csv_string
  end

  def self.app_content_set_csv(phone_number)
    csv_string = CSV.generate do |csv|
      csv << ["Issue", "App Phone Number", "Message From", "Message URL", "Header Color", "Short Title", "Call In Code Digits", "Feedback Form URL"]
      csv << ["CityVoice", phone_number, "CityVoice Maintainers", "/assets/welcome.mp3", "#6DC6AD", "CityVoice", "3", "https://docs.google.com/a/codeforamerica.org/forms/d/1CD4FyRCHh5C7g44ueINFtqM9Ulv1c3krhRn9COIUwgA/viewform"]
    end
    csv_string
  end
end
