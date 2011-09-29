require 'simplecov'
SimpleCov.start

require File.join(File.dirname(__FILE__), '..', 'techno.rb')

require 'rspec'
require 'rack/test'
require 'webmock/rspec'
set :environment, :test

RSpec.configure do |conf|
  conf.include Rack::Test::Methods

  def fixture_path
    File.expand_path('../fixtures', __FILE__)
  end

  def fixture(file)
    File.new(fixture_path + '/' + file)
  end

  def process_zip
   '{"result":
                {"sessionId":"abc123",
                  "callId":"xyzABC",
                  "state":"ANSWERED",
                  "sessionDuration":9,
                  "sequence":1,
                  "complete":true,
                  "error":null,
                  "actions":{
                      "name":"zip",
                      "attempts":1,
                      "disposition":"SUCCESS",
                      "confidence":100,
                      "interpretation":"60647",
                      "utterance":"6 0 6 4 7",
                      "value":"60647",
                      "xml":"<?xml version=\"1.0\"?>\r\n<result grammar=\"0@4e1adcec.vxmlgrammar\">\r\n <interpretation grammar=\"0@4e1adcec.vxmlgrammar\" confidence=\"100\">\r\n \r\n <input mode=\"dtmf\">dtmf-6 dtmf-0 dtmf-6 dtmf-4 dtmf-7<\/input>\r\n <\/interpretation>\r\n<\/result>\r\n"}
                  }
                }'


  end

  def process_selection
    '{"result":
                {"sessionId":"abc123",
                  "callId":"xyz456",
                  "state":"ANSWERED",
                  "sessionDuration":28,
                  "sequence":2,
                  "complete":true,
                  "error":null,
                  "actions":{
                    "name":"selection",
                    "attempts":1,
                    "disposition":
                    "SUCCESS",
                    "confidence":100,
                    "interpretation":"1",
                    "utterance":"1",
                    "value":"1",
                    "xml":"<?xml version=\"1.0\"?>\r\n<result grammar=\"1@4e1adcec.vxmlgrammar\">\r\n <interpretation grammar=\"1@4e1adcec.vxmlgrammar\" confidence=\"100\">\r\n \r\n <input mode=\"dtmf\">dtmf-1<\/input>\r\n <\/interpretation>\r\n<\/result>\r\n"}
                  }
                }'

  end

end

def app
  Sinatra::Application
end


