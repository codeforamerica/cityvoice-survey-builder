module CityvoiceCsvGenerator
  def self.locations_csv(locations)
    csv_string = CSV.generate do |csv|
      csv << %w(Name Lat Long)
      locations.each do |loc|
        csv << [loc["name"], loc["lat"], loc["lng"]]
      end
    end
  end

  class QuestionsCsv
  end
end
