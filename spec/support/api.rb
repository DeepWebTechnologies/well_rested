def base_path
  auth = 'user:password'
  base = "#{Base.server}"
end

def mock_api
  FakeWeb.allow_net_connect = false
  Base.server = 'localhost:8089'
  API.new
end

=begin
def live_api
  require 'restclient/components'
  require 'rack/cache'
  puts "RestClient: Enabling Rack::Cache"
  RestClient.enable Rack::Cache

  FakeWeb.allow_net_connect = true
  FakeWeb.clean_registry

  DWC::Base.server = 'localhost:9089'

  api = API.new
end
=end
