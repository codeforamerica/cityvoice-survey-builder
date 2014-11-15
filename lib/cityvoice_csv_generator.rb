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
end
