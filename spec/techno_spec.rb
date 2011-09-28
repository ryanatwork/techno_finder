require File.dirname(__FILE__) + '/spec_helper'

describe 'TechnoFinder Application' do
describe '/index.json' do
    it "should respond to an incoming call" do
      json = '{"session":
                {"id":"d7a7f84ee0b497e73d152a62c99b1fc9",
                  "accountId":"12345",
                  "timestamp":"2011-09-25T18:36:30.737Z",
                  "userType":"HUMAN",
                  "initialText":null,
                  "callId":"abc123",
                  "to":{
                    "id":"6615551234",
                    "name":"+16615551234",
                    "channel":"VOICE",
                    "network":"SIP"
                    },
                  "from":{
                    "id":"661-444-5555",
                    "name":"+16614445555",
                    "channel":"VOICE",
                    "network":"SIP"
                    }
                  }
              }'

      post '/index.json',json
      last_response.body.should == "{\"tropo\":[{\"ask\":{\"name\":\"zip\",\"bargein\":true,\"timeout\":60,\"attempts\":2,\"say\":[{\"event\":\"timeout\",\"value\":\"Sorry, I did not hear anything.\"},{\"event\":\"nomatch:1 nomatch:2\",\"value\":\"Oops, that wasn't a five-digit zip code.\"},{\"value\":\"Please enter your zip code to search for public technology resources in your area.\"}],\"choices\":{\"value\":\"[5 DIGITS]\"}}},{\"on\":{\"event\":\"hangup\",\"next\":\"/hangup.json\"}},{\"on\":{\"event\":\"continue\",\"next\":\"/process_zip.json\"}}]}"
    end
  end

end
