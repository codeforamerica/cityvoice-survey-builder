ENV['RACK_ENV'] = 'test'

require 'rspec'
require 'rack/test'
require 'pry'

require File.expand_path('../../cityvoice_builder_heroku', __FILE__)
require File.expand_path('../rack_spec_helpers', __FILE__)

RSpec.configure do |config|
  config.include RackSpecHelpers
  config.before do
    self.app = CityvoiceBuilderHeroku
  end
end
