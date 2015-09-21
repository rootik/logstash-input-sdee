# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/http_client"
require "yaml"
require "uri"
require "time"
require "rexml/document"
require "socket" # for Socket.gethostname
require "manticore"
include REXML

# Note. This plugin is a WIP! Things will change and break!
#
# Reads from a list of urls and decodes the body of the response with a codec
# The config should look like this:
#
# input {
#   sdee {
#     # Supports all options supported by ruby's Manticore HTTP client
#     http {
#       method => get
#       url => "http://ciscoips"
#       headers => {
#         Accept => "text/xml"
#       }
#       auth => {
#         user => "cisco"
#         password => "p@ssw0rd"
#       }
#     request_timeout => 60
#     }
#     session_file => "/var/lib/elasticsearch/session.db"
#     interval => 60
#     codec => "plain"
#     # A hash of request metadata info (timing, response headers, etc.) will be sent here
#     metadata_target => "_sdee_metadata"
#   }
# }
#
# output {
#   stdout {
#     codec => rubydebug
#   }
# }

class LogStash::Inputs::SDEE < LogStash::Inputs::Base
  include LogStash::PluginMixins::HttpClient

  config_name "sdee"
  
  default :codec, "plain"

  # A Hash of urls in this format : "name" => "url"
  # The name and the url will be passed in the outputed event
  #
  config :http, :validate => :hash, :required => true

  # How often  (in seconds) the urls will be called
  config :interval, :validate => :number, :required => true

  # Define the target field for placing the received data. If this setting is omitted, the data will be stored at the root (top level) of the event.
  config :target, :validate => :string

  # If you'd like to work with the request/response metadata
  # Set this value to the name of the field you'd like to store a nested
  # hash of metadata.
  config :metadata_target, :validate => :string, :default => '@metadata'
  #, :default => '@metadata'


  # A local File to store CIDEE SubscriptionID and SessionID
  config :session_file, :validate => :string, :required => true
  

  
  public
  def register
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)
    @remaining = 0
    setup_request!(@http)

    @logger.info("Registering SDEE Input", :type => @type,
                 :http => @http, :interval => @interval, :timeout => @timeout)

    #subscribe to SDEE and store session data
    @session = subscribe(@request)

    newurl = URI.join(@http["url"], "cgi-bin/sdee-server?subscriptionId=#{@session[:subscriptionid]}&confirm=yes&maxNbrOfEvents=150&timeout=5&sessionId=#{@session[:sessionid]}")

    @request[1] = newurl.to_s
    rescue StandardError, java.lang.Exception => e
     @logger.error? && @logger.error("SDEE subscription error!",
                                    :exception => e,
                                    :exception_message => e.message,
                                    :exeption_backtrace => e.backtrace
     )

  end

  private
  def subscribe(request)
    # recover from ungraceful shutdown first
    if File.exist?(@session_file)
      yaml = YAML.load_file(@session_file)
      if (defined?(yaml) && yaml != nil)
        unsubscribe(request,yaml)
      end
    end

    url = URI.join(@http["url"], "cgi-bin/sdee-server?action=open&evIdsAlert&force=yes")
    request[1] = url.to_s
    session = Hash.new
    method, *request_opts = request
    client.async.send(method, *request_opts).
      on_success {|response| session = handle_subscription(request, response)}.
      on_failure {|exception| http_error(request, exception)}
    client.execute!
    raise LogStash::ConfigurationError, "Subscription Error! Check your configuration for host url,user,password." unless session
    session
  end
  
  private
  def handle_subscription(request, response)
    body = response.body    
    xml = REXML::Document.new body.to_s
    session = Hash.new
    sessionid = REXML::XPath.first(xml, "//sd:sessionId")
    subscriptionid = REXML::XPath.first(xml, "//sd:subscriptionId")
    session[:sessionid] = sessionid.text if sessionid
    session[:subscriptionid] = subscriptionid.text if subscriptionid
    File.open(@session_file, 'w') {|f| f.write session.to_yaml }
    session
  end
  
  private
  def http_error(request, exeption)
      @logger.error? && @logger.error("Cannot read URL or send the error as an event! Check your configuration for host url,user,password.",
                                        :request => structure_request(request),
                                        :exception => exeption.to_s,
                                        :exception_backtrace => exeption.backtrace    
      )
  end

  private
  def unsubscribe(request,session)
    #unsubscribe and remove session data file
    url = URI.join(@http["url"], "cgi-bin/sdee-server?action=close&subscriptionId=#{session[:subscriptionid]}&sessionId=#{session[:sessionid]}")
    request[1] = url.to_s
    method, *request_opts = request
    client.async.send(method, *request_opts).
      on_success {|response| remove_session}.
      on_failure {|exception| http_error(request, exception)}
    client.execute!
  end
  
  private
  def remove_session
    if File.exist?(@session_file) 
     File.delete(@session_file)
    end
  end

  private
  def setup_request!(http)
    @request = normalize_request(http)
  end

  private
  def normalize_request(http)
    if http.is_a?(Hash)
      # The client will expect keys / values
      spec = Hash[http.clone.map {|k,v| [k.to_sym, v] }] # symbolize keys

      # method and url aren't really part of the options, so we pull them out
      method = (spec.delete(:method) || :get).to_sym.downcase
      url = spec.delete(:url)

      # We need these strings to be keywords!
      spec[:auth] = {user: spec[:auth]["user"], pass: spec[:auth]["password"]} if spec[:auth]

      res = [method, url, spec]
    else
      raise LogStash::ConfigurationError, "Invalid request spec: '#{http}', expected a Hash!"
    end

    validate_request!(http, res)
    res
  end

  private
  def validate_request!(http, request)
    method, url, spec = request

    raise LogStash::ConfigurationError, "Invalid URL #{url}" unless URI::DEFAULT_PARSER.regexp[:ABS_URI].match(url)

    raise LogStash::ConfigurationError, "No URL provided for request! #{http}" unless url
    if spec && spec[:auth]
      if !spec[:auth][:user]
        raise LogStash::ConfigurationError, "Auth was specified, but 'user' was not!"
      end
      if !spec[:auth][:pass]
        raise LogStash::ConfigurationError, "Auth was specified, but 'password' was not!"
      end
    end

    request
  end

  public
  def run(queue)
    while true
      begin
        Stud.interval(@interval) do
          begin
            run_once(queue)
          end while (@remaining > 0)
        end
      rescue EOFError, LogStash::ShutdownSignal
        break
      end
    end
  end

  public
  def teardown
    @logger.debug? && @logger.debug("SDEE shutting down")
    unsubscribe(@request,@session) rescue nil
    finished
  end # def teardown

  private
  def run_once(queue)
    request_async(queue, @request)
    client.execute!
  end

  private
  def request_async(queue, request)
    @logger.debug? && @logger.debug("Fetching URL", :url => request)
    started = Time.now

    method, *request_opts = request
    client.async.send(method, *request_opts).
      on_success {|response| handle_success(queue, request, response, Time.now - started)}.
      on_failure {|exception| handle_failure(queue, request, exception, Time.now - started)
    }
  end

  private
  def handle_success(queue, request, response, execution_time)
    decode(response.body).each_pair do |id,decoded|
      event = LogStash::Event.new(decoded)
      handle_decoded_event(queue, request, response, event, execution_time)
    end
  end

  private
  def handle_decoded_event(queue, request, response, event, execution_time)
    apply_metadata(event, request, response, execution_time) if @metadata_target
    decorate(event)
    queue << event
  rescue StandardError, java.lang.Exception => e
    @logger.error? && @logger.error("Error eventifying response!",
                                    :exception => e,
                                    :exception_message => e.message,
                                    :exeption_backtrace => e.backtrace,
                                    :url => request,
                                    :response => response
    )
  end

  private
  # Beware, on old versions of manticore some uncommon failures are not handled
  def handle_failure(queue, request, exception, execution_time)
    event = LogStash::Event.new
    apply_metadata(event, request)

    event.tag("_sdee_failure")

    # This is also in the metadata, but we send it anyone because we want this
    # persisted by default, whereas metadata isn't. People don't like mysterious errors
    event["sdee_failure"] = {
      "request" => structure_request(request),
      "error" => exception.to_s,
      "backtrace" => exception.backtrace,
      "runtime_seconds" => execution_time
   }

    queue << event
  rescue StandardError, java.lang.Exception => e
      @logger.error? && @logger.error("Cannot read URL or send the error as an event!",
                                      :exception => e,
                                      :exception_message => e.message,
                                      :exception_backtrace => e.backtrace,
                                      :url => request
      )
  end

  private
  def apply_metadata(event, request, response=nil, execution_time=nil)
    #return unless @metadata_target
    event[@metadata_target] = event_metadata(request, response, execution_time)
  end

  private
  def event_metadata(request, response=nil, execution_time=nil)
    m = {
        "host" => @host,
        "request" => structure_request(request),
      }

    m["runtime_seconds"] = execution_time

    if response
      m["code"] = response.code
      m["response_headers"] = response.headers
      m["response_message"] = response.message
      m["times_retried"] = response.times_retried
    end
    m
  end

  private
  # Turn [method, url, spec] requests into a hash for friendlier logging / ES indexing
  def structure_request(request)
    method, url, spec = request
    # Flatten everything into the 'spec' hash, also stringify any keys to normalize
    Hash[(spec||{}).merge({
      "method" => method.to_s,
      "url" => url,
    }).map {|k,v| [k.to_s,v] }]
  end
  
  private
  def decode(body)
    events = Hash.new    
    xml = REXML::Document.new body.to_s
    err = REXML::XPath.first(xml, "//env:Reason") if REXML::XPath.first(xml, "//env:Fault")
    err = err.text.to_s if err
    if err && err == "Subscription does not exist"
        subscribe(@request)
    end
    rem = REXML::XPath.first(xml, "//sd:remaining-events")
    @remaining = rem.text.to_i if rem
    # We use own XML parsing to keep things simple to the user
    xml.elements.each("*/env:Body/sd:events/sd:evIdsAlert") do |element|
      eid =  element.attributes["eventId"]
      events[eid] = {      
        "@timestamp" => Time.at(REXML::XPath.first(element,"./sd:time").text.to_i/10**9).iso8601,
        "timezone" => REXML::XPath.first(element,"./sd:time").attributes["timeZone"],
        "tz_offset" => REXML::XPath.first(element,"./sd:time").attributes["offset"],
        "event_id" => element.attributes["eventId"].to_s,
        "severity" => element.attributes["severity"].to_s,
        "vendor" => element.attributes["vendor"].to_s,
        "host_id" => REXML::XPath.first(element,"./sd:originator/sd:hostId").text,
        "app_name" => REXML::XPath.first(element,"./sd:originator/cid:appName").text,
        "app_instance_id" => REXML::XPath.first(element,"./sd:originator/cid:appInstanceId").text,
        "description" => REXML::XPath.first(element,"./sd:signature").attributes["description"],
        "sig_id" => REXML::XPath.first(element,"./sd:signature").attributes["id"],
        "sig_version" => REXML::XPath.first(element,"./sd:signature").attributes["cid:version"],
        "sig_type" => REXML::XPath.first(element,"./sd:signature").attributes["cid:type"],
        "sig_created" => REXML::XPath.first(element,"./sd:signature").attributes["created"],
        "subsig_id" => REXML::XPath.first(element,"./sd:signature/cid:subsigId").text,
        "sig_details" => REXML::XPath.first(element,"./sd:signature/cid:sigDetails").text,
        "interface_group" => REXML::XPath.first(element,"./sd:interfaceGroup").text,
        "vlan" => REXML::XPath.first(element,"./sd:vlan").text,
        "attacker_addr" => REXML::XPath.first(element,"./sd:participants/sd:attacker/sd:addr").text,
        "attacker_locality" => REXML::XPath.first(element,"./sd:participants/sd:attacker/sd:addr").attributes["locality"],
        "target_addr" => REXML::XPath.first(element,"./sd:participants/sd:target/sd:addr").text,
        "target_os_source" => REXML::XPath.first(element,"./sd:participants/sd:target/cid:os").attributes["idSource"],
        "target_os_type" => REXML::XPath.first(element,"./sd:participants/sd:target/cid:os").attributes["type"],
        "target_os_relevance" => REXML::XPath.first(element,"./sd:participants/sd:target/cid:os").attributes["relevance"],
        # Need? to parse <cid:summary cid:final='true' cid:initialAlert='6824288769384' cid:summaryType='Regular'>2</cid:summary>
        "alert_details" => REXML::XPath.first(element,"./cid:alertDetails").text.tr('\\"', '\''),
        "risk_rating" => REXML::XPath.first(element,"./cid:riskRatingValue").text,
        "risk_target" => REXML::XPath.first(element,"./cid:riskRatingValue").attributes["targetValueRating"],
        "risk_attacker" => REXML::XPath.first(element,"./cid:riskRatingValue").attributes["attackRelevanceRating"],
        "threat_rating" => REXML::XPath.first(element,"./cid:threatRatingValue").text,
        "interface" => REXML::XPath.first(element,"./cid:interface").text,
        "host" => URI.parse(@http["url"]).host,
        "tags" => "SDEE"
        }
        events[element.attributes["eventId"]].merge!({"attacker_port" => REXML::XPath.first(element,"./sd:participants/sd:attacker/sd:port").text}) if REXML::XPath.first(element,"./sd:participants/sd:attacker/sd:port")
        events[element.attributes["eventId"]].merge!({"target_port" => REXML::XPath.first(element,"./sd:participants/sd:target/sd:port").text}) if REXML::XPath.first(element,"./sd:participants/sd:target/sd:port")
        message = events[eid]
        events[eid].merge!({"message" => "IdsAlert: #{events[eid]["description"]} Attacker: #{events[eid]["attacker_addr"]} Target: #{events[eid]["target_addr"]} SigId: #{events[eid]["sig_id"]}"})
      end
      events 
  end
end
