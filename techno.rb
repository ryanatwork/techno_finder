require 'sinatra'
require 'json'
require 'net/http'
require 'haml'
require 'windy'
require 'geocoder'
require 'tropo-webapi-ruby'

# To manage the web session coookies
use Rack::Session::Pool

# Resource called by the Tropo WebAPI URL setting
post '/index.json' do
  # Fetches the HTTP Body (the session) of the POST and parse it into a native Ruby Hash object
  v = Tropo::Generator.parse request.env["rack.input"].read

  # Fetching certain variables from the resulting Ruby Hash of the session details
  # into Sinatra/HTTP sessions; this can then be used in the subsequent calls to the
  # Sinatra application
  session[:from] = v[:session][:from]
  session[:network] = v[:session][:to][:network]
  session[:channel] = v[:session][:to][:channel]

  # Create a Tropo::Generator object which is used to build the resulting JSON response
  t = Tropo::Generator.new
    # If there is Initial Text available, we know this is an IM/SMS/Twitter session and
    # not voice
    if v[:session][:initial_text]
      # Add an 'ask' WebAPI method to the JSON response with appropriate options
      t.ask :name => 'initial_text', :choices => { :value => "[ANY]"}
      # Set a session variable with the zip the user sent when they sent the IM/SMS/Twitter
      # Request
      session[:zip] = v[:session][:initial_text]
    else
      # If this is a voice session, then add a voice-oriented ask to the JSON response
      # with the appropriate options
      t.ask :name => 'zip', :bargein => true, :timeout => 60, :attempts => 2,
          :say => [{:event => "timeout", :value => "Sorry, I did not hear anything."},
                   {:event => "nomatch:1 nomatch:2", :value => "Oops, that wasnt a five-digit zip code."},
                   {:value => "Please enter your zip code to search for public technology resources in your area."}],
                    :choices => { :value => "[5 DIGITS]"}
    end

    # Add a 'hangup' to the JSON response and set which resource to go to if a Hangup event occurs on Tropo
    t.on :event => 'hangup', :next => '/hangup.json'
    # Add an 'on' to the JSON response and set which resource to go when the 'ask' is done executing
    t.on :event => 'continue', :next => '/process_zip.json'

  # Return the JSON response via HTTP to Tropo
  t.response
end

# The next step in the session is posted to this resource when the 'ask' is completed in 'index.json'
post '/process_zip.json' do
  # Fetch the HTTP Body (the session) of the POST and parse it into a native Ruby Hash object
  v = Tropo::Generator.parse request.env["rack.input"].read

  # Create a Tropo::Generator object which is used to build the resulting JSON response
  t = Tropo::Generator.new
    # If no intial text was captured, use the zip in response to the ask in the previous route
    session[:zip] = v[:result][:actions][:zip][:value].gsub(" ","") unless session[:zip]

    begin
      technology = Windy.views.find_by_id("nen3-vcxj")
      places = technology.rows
      session[:data]  = places.find_all_by_zip(session[:zip])
    rescue
      # Add a 'say' to the JSON response
      t.say "It looks like something went wrong with our data source. Please try again later."
      t.hangup
    end
    # List the opportunities to the user in the form of a question. The selected opportunity will be handled in the next route.
    if session[:data].size > 0
      # Add a 'say' to the JSON response
      t.say "Here are #{session[:data].size} locations. Press the location number you want more information about."
      items_say = []
      session[:data].each_with_index{|item,i| items_say << "Location ##{i+1} #{item.facility}"}
      # Add an 'ask' to the JSON response
      t.ask :name => 'selection', :bargein => true, :timeout => 60, :attempts => 1,
          :say => [{:event => "nomatch:1", :value => "That wasn't a one-digit opportunity number. Here are your choices: "},
                   {:value => items_say.join(", ")}], :choices => { :value => "[1 DIGITS]"}
    else
      # Add a 'say' to the JSON response
      t.say "No public technology resources found in that zip code. Please try again later."
    end

    # Add an 'on' to the JSON reponse and set which resource to go to when the 'ask' is done executing
    t.on  :event => 'continue', :next => '/process_selection.json'
    # Add a 'hangup' to the JSON reponse and set which resource to go to if a Hangup event occurs on Tropo
    t.on  :event => 'hangup', :next => '/hangup.json'

  # Return the JSON response via HTTP to Tropo
  t.response
end

# The next step in the session is posted to this resource when the 'ask' is completed in 'process_zip.json'
post '/process_selection.json' do
  # Fetch the HTTP Body (the session) of the POST and parse it into a native Ruby Hash object
  v = Tropo::Generator.parse request.env["rack.input"].read

  # Create a Tropo::Generator object which is used to build the resulting JSON response
  t = Tropo::Generator.new
    # If we have a valid response from the last ask, do this section
    if v[:result][:actions][:selection][:value]
      item = session[:data][v[:result][:actions][:selection][:value].to_i-1]
      session[:say_string] = "" # storing in a session variable to send it via text message later (if the user wants)
      session[:say_string] += "Information about location #{item.facility} is as follows: "
      session[:say_string] += "Location: #{item.address} "
      session[:say_string] += "Hours: #{item.hours}"
      session[:say_string] += "Phone: #{item.phone}"
      t.say session[:say_string]

      # Ask the user if they would like an SMS sent to them
      t.ask :name => 'send_sms', :bargein => true, :timeout => 60, :attempts => 1,
            :say => [{:event => "nomatch:1", :value => "That wasnt a valid answer. "},
                   {:value => "Would you like to have a text message sent to you?
                               Press 1 or say 'yes' to get a text message; Press 2 or say 'no' to conclude this session."}],
            :choices => { :value => "true(1,yes), false(2,no)"}
    else # No opportunity found
      t.say "No location with that value. Please try again."
    end

    # Add an 'on' to the JSON response and set which resource to go to when the 'ask' is done executing
    t.on  :event => 'continue', :next => '/send_text_message.json'
    # Add a 'hangup' to the JSON response and set which resource to go to if a Hangup event occurs on Tropo
    t.on  :event => 'hangup', :next => '/hangup.json'

  # Return the JSON response via HTTP to Tropo
  t.response
end

# The next step in the session is posted to this resource when the 'ask' is completed in 'process_selection.json'
post '/send_text_message.json' do
  # Fetch the HTTP Body (the session) of the POST and parse it into a native Ruby Hash object
  v = Tropo::Generator.parse request.env["rack.input"].read

  # Create a Tropo::Generator object which is used to build the resulting JSON response
  t = Tropo::Generator.new
    if v[:result][:actions][:number_to_text] # The caller provided a phone # to text message
      t.message({
        :to => v[:result][:actions][:number_to_text][:value],
        :network => "SMS",
        :say => {:value => session[:say_string]}})
      t.say "Message sent."
    else # We dont have a number, so either ask for it if they selected to send a text message, or send to goodbye.json
      if v[:result][:actions][:send_sms][:value] == "true"
        t.ask :name => 'number_to_text', :bargein => true, :timeout => 60, :required => false, :attempts => 2,
              :say => [{:event => "timeout", :value => "Sorry, I did not hear anything."},
                     {:event => "nomatch:1 nomatch:2", :value => "Oops, that wasn't a 10-digit number."},
                     {:value => "What 10-digit phone number would you like to send the information to?"}],
                      :choices => { :value => "[10 DIGITS]"}
        next_url = '/send_text_message.json'
      end # No need for an else, send them off to /goodbye.json
    end

    # Tell it to say goodbye if there is no next_url set above
    next_url = '/goodbye.json' if next_url.nil?
    # Add an 'on' to the JSON response and set which resource to go to when the 'ask' is done executing
    t.on  :event => 'continue', :next => next_url
    # Add a 'hangup' to the JSON response and set which resource to go to if a Hangup event occurs on Tropo
    t.on  :event => 'hangup', :next => '/hangup.json'

  # Return the JSON response via HTTP to Tropo
  t.response
end

# The next step in the session is posted to this resource when the 'ask' is completed in 'send_text_message.json'
post '/goodbye.json' do
  # Fetch the HTTP Body (the session) of the POST and parse it into a native Ruby Hash object
  v = Tropo::Generator.parse request.env["rack.input"].read

  # Create a Tropo::Generator object which is used to build the resulting JSON response
  t = Tropo::Generator.new
    if session[:channel] == "VOICE"
      t.say "That's all. Communication services donated by tropo dot com, data by all for good dot org. Have a nice day. Goodbye."
    else # For text users, we can give them a URL (most clients will make the links clickable)
      t.say "That's all. Communication services donated by http://Tropo.com; data by http://data.cityofchicago.org/"
    end
    t.hangup

    # Add a 'hangup' to the JSON response and set which resource to go to if a Hangup event occurs on Tropo
    t.on  :event => 'hangup', :next => '/hangup.json'
  t.response
end

# The next step in the session is posted to this resource when any of the resources do a hangup
post '/hangup.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read
  puts " Call complete (CDR received). Call duration: #{v[:result][:session_duration]} second(s)"
end



get '/' do

    b = JSON.parse(Net::HTTP.get(URI.parse("http://data.cityofchicago.org/api/views/nen3-vcxj/rows.json")))
    us = [41.864447,-87.644806]
    a = b["data"].min_by {|x| dist(x,us)}
    "#{a}"
end

get '/address/:location' do

    b = JSON.parse(Net::HTTP.get(URI.parse("http://data.cityofchicago.org/api/views/nen3-vcxj/rows.json")))

    location = params[:location]

    us = Geocoder.coordinates(location)
    a = b["data"].min_by {|x| dist(x,us)}
    "#{a[1]}"

end



def dist(entry,loc)
  entry.last[1..2].map(&:to_f).zip(loc).inject(0) {|s,(c1,c2)| s+(c1-c2)**2}
end
