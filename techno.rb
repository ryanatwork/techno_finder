require 'sinatra'
require 'json'
require 'net/http'
require 'haml'
require 'windy'
require 'geocoder'
require 'tropo-webapi-ruby'

use Rack::Session::Pool

post '/index.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read

  session[:from] = v[:session][:from]
  session[:network] = v[:session][:to][:network]
  session[:channel] = v[:session][:to][:channel]

  t = Tropo::Generator.new
    if v[:session][:initial_text]
      t.ask :name => 'initial_text', :choices => { :value => "[ANY]"}
      session[:zip] = v[:session][:initial_text]
    else
      t.say "Welcome to techno finder; search for public technology resources in Chicago"
      t.ask :name => 'zip', :bargein => true, :timeout => 60, :attempts => 2,
          :say => [{:event => "timeout", :value => "Sorry, I did not hear anything."},
                   {:event => "nomatch:1 nomatch:2", :value => "Oops, that wasnt a five-digit zip code."},
                   {:value => "Please enter your zip code to search."}],
                    :choices => { :value => "[5 DIGITS]", :mode => "dtmf"}
    end

    t.on :event => 'hangup', :next => '/hangup.json'
    t.on :event => 'continue', :next => '/process_zip.json'

  t.response
end

post '/process_zip.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read

  t = Tropo::Generator.new

  session[:zip] = v[:result][:actions][:zip][:value].gsub(" ","") unless session[:zip]

  begin
    technology = Windy.views.find_by_id("nen3-vcxj")
    places = technology.rows
    session[:data]  = places.find_all_by_zip(session[:zip])
  rescue
    t.say "It looks like something went wrong with our data source. Please try again later."
    t.hangup
  end
    if session[:data].size > 0
      t.say "Here are #{session[:data].size} locations. Press the location number you want more information about."
      items_say = []
      session[:data].each_with_index{|item,i| items_say << "Location ##{i+1} #{item.facility}"}
      t.ask :name => 'selection', :bargein => true, :timeout => 60, :attempts => 1,
          :say => [{:event => "nomatch:1", :value => "That wasn't a one-digit opportunity number. Here are your choices: "},
                   {:value => items_say.join(", ")}], :choices => { :value => "[1 DIGITS]", :mode => "dtmf"}
    else
      t.say "No public technology resources found in that zip code. Please try again later."
    end

    t.on  :event => 'continue', :next => '/process_selection.json'
    t.on  :event => 'hangup', :next => '/hangup.json'

  t.response
end

post '/process_selection.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read

  t = Tropo::Generator.new
    if v[:result][:actions][:selection][:value]
      item = session[:data][v[:result][:actions][:selection][:value].to_i-1]
      say_string = ""
      say_string += "Information about location #{item.facility} is as follows: "
      say_string += "Location: #{item.address};"
      say_string += "Type: #{item.type};"
      say_string += "Hours: #{fix_hours(item.hours)};"
      say_string += "Phone: #{item.phone};"
      say_string += "Appointment: #{item.appointment};"
      say_string += "Internet: #{item.internet ? 'Yes' : 'No'};"
      say_string += "WiFi: #{item.wifi ? 'Yes' : 'No'} "
      say_string += "Training: #{item.training ? 'Yes' : 'No'};"
      t.say say_string

      session[:say_string] = "" # storing in a session variable to send it via text message later (if the user wants)
      session[:say_string] += "#{item.facility} "
      session[:say_string] += "#{item.address} "
      session[:say_string] += "Type:#{item.type} "
      session[:say_string] += "Hours:#{item.hours} "
      session[:say_string] += "Phone:#{item.phone} "
      session[:say_string] += "Appointment:#{item.appointment} "
      session[:say_string] += "Internet:#{item.internet ? 'Yes' : 'No'} "
      session[:say_string] += "WiFi:#{item.wifi ? 'Yes' : 'No'} "
      session[:say_string] += "Training:#{item.training ? 'Yes' : 'No'} "

      t.ask :name => 'send_sms', :bargein => true, :timeout => 60, :attempts => 1,
            :say => [{:event => "nomatch:1", :value => "That wasnt a valid answer. "},
                   {:value => "Would you like to have a text message sent to you?
                               Press 1 to get a text message; Press 2 to conclude this session."}],
            :choices => { :value => "true(1), false(2)", :mode => "dtmf"}
    else
      t.say "No location with that value. Please try again."
    end

    t.on  :event => 'continue', :next => '/send_text_message.json'
    t.on  :event => 'hangup', :next => '/hangup.json'

  t.response
end

post '/send_text_message.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read

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
                      :choices => { :value => "[10 DIGITS]", :mode => "dtmf"}
        next_url = '/send_text_message.json'
      end
    end

    next_url = '/goodbye.json' if next_url.nil?
    t.on  :event => 'continue', :next => next_url
    t.on  :event => 'hangup', :next => '/hangup.json'

  t.response
end

post '/goodbye.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read

  # Create a Tropo::Generator object which is used to build the resulting JSON response
  t = Tropo::Generator.new
    if session[:channel] == "VOICE"
      t.say "That's all. Communication services donated by tropo dot com, data by data dot city of chicago dor org. Have a nice day. Goodbye."
    else # For text users, we can give them a URL (most clients will make the links clickable)
      t.say "That's all. Communication services donated by http://Tropo.com; data by http://data.cityofchicago.org/"
    end
    t.hangup

    t.on  :event => 'hangup', :next => '/hangup.json'
  t.response
end

post '/hangup.json' do
  v = Tropo::Generator.parse request.env["rack.input"].read
  puts " Call complete (CDR received). Call duration: #{v[:result][:session_duration]} second(s)"
end

def fix_hours(hours)
  hours.gsub('-', ' to ')
end

def get_technology
  technology = Windy.views.find_by_id("nen3-vcxj")
  places = technology.rows
  get_technology  = places.find_all_by_zip("60647")
end


get '/' do
  @tech = get_technology
  @items_say = []
  @tech.each_with_index{|item,i| @items_say << "Location ##{i+1} #{item.facility}"}
  haml :index
end

get '/address/:location' do

  b = JSON.parse(Net::HTTP.get(URI.parse("http://data.cityofchicago.org/api/views/nen3-vcxj/rows.json")))

  if params[:location].nil?
    location = [41.864447,-87.644806]
  else
    location = params[:location]
  end

  us = Geocoder.coordinates(location)
  a = b["data"].min_by {|x| dist(x,us)}
  "#{a[1]}"

end

def dist(entry,loc)
  entry.last[1..2].map(&:to_f).zip(loc).inject(0) {|s,(c1,c2)| s+(c1-c2)**2}
end
