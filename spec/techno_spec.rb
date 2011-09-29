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
      last_response.body.should == "{\"tropo\":[{\"say\":[{\"value\":\"Welcome to techno finder; search for public technology resources in Chicago\"}]},{\"ask\":{\"name\":\"zip\",\"bargein\":true,\"timeout\":60,\"attempts\":2,\"say\":[{\"event\":\"timeout\",\"value\":\"Sorry, I did not hear anything.\"},{\"event\":\"nomatch:1 nomatch:2\",\"value\":\"Oops, that wasnt a five-digit zip code.\"},{\"value\":\"Please enter your zip code to search.\"}],\"choices\":{\"value\":\"[5 DIGITS]\",\"mode\":\"dtmf\"}}},{\"on\":{\"event\":\"hangup\",\"next\":\"/hangup.json\"}},{\"on\":{\"event\":\"continue\",\"next\":\"/process_zip.json\"}}]}"
    end
  end

  describe '/process_zip.json' do
    before do
      stub_request(:get, "http://data.cityofchicago.org/api/views?limit=200&page=1").
        to_return(:status => 200, :body => fixture("technology_resources.json"))
      stub_request(:get, "http://data.cityofchicago.org/api/views/nen3-vcxj/rows.json").
        to_return(:status => 200, :body => fixture("tech_rows.json"))
    end

    it "should find locations in the zip code and return json" do
      post '/process_zip.json', process_zip
      last_response.body.should == "{\"tropo\":[{\"say\":[{\"value\":\"Here are 8 locations. Press the location number you want more information about.\"}]},{\"ask\":{\"name\":\"selection\",\"bargein\":true,\"timeout\":60,\"attempts\":1,\"say\":[{\"event\":\"nomatch:1\",\"value\":\"That wasn't a one-digit opportunity number. Here are your choices: \"},{\"value\":\"Location #1 Bucktown-Wicker Park, Location #2 Humboldt Park , Location #3 Logan Square, Location #4 Monroe Elementary School, Location #5 Community TV Network Youth Media Ctr., Location #6 Workforce Development Office CTC, Location #7 La Casa Norte, Location #8 Hispanic Housing Development Corporation\"}],\"choices\":{\"value\":\"[1 DIGITS]\",\"mode\":\"dtmf\"}}},{\"on\":{\"event\":\"continue\",\"next\":\"/process_selection.json\"}},{\"on\":{\"event\":\"hangup\",\"next\":\"/hangup.json\"}}]}"
    end
  end

  describe "/process_selection.json" do
    before do
      post '/process_zip.json', process_zip
    end

    it "should list the results and return json" do
      json = '{"result":
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

      post '/process_selection.json', json
      last_response.body.should == "{\"tropo\":[{\"say\":[{\"value\":\"Information about location Bucktown-Wicker Park is as follows: Location: 1701 N. Milwaukee Avenue Hours: M-W: 12PM-8PM; TU, TH: 10AM-6PM; F-SA: 9AM-5PM; SU: ClosedPhone: (312) 744-6022\"}]},{\"ask\":{\"name\":\"send_sms\",\"bargein\":true,\"timeout\":60,\"attempts\":1,\"say\":[{\"event\":\"nomatch:1\",\"value\":\"That wasnt a valid answer. \"},{\"value\":\"Would you like to have a text message sent to you?\\n                               Press 1 to get a text message; Press 2 to conclude this session.\"}],\"choices\":{\"value\":\"true(1), false(2)\",\"mode\":\"dtmf\"}}},{\"on\":{\"event\":\"continue\",\"next\":\"/send_text_message.json\"}},{\"on\":{\"event\":\"hangup\",\"next\":\"/hangup.json\"}}]}"
    end
  end

end
