require 'rest-client'
require 'json'
require 'active_support/core_ext/object/to_query'
require 'key_transformer'
require 'cgi'

require 'well_rested/utils'

module WellRested
  # All REST requests are made through an API object.
  # API objects store cross-resource settings such as user and password (for HTTP basic auth).
  class API
    include WellRested  # for logger
    include WellRested::Utils

    attr_accessor :user
    attr_accessor :password
    attr_accessor :default_path_parameters
    attr_accessor :client
    attr_reader   :last_response

    def initialize(path_params = {})
      self.default_path_parameters = path_params.with_indifferent_access
      self.client = RestClient
    end

    ##
    # Issue a request of method 'method' (:get, :put, :post, :delete) for the resource identified by 'klass'.
    # If it is a PUT or a POST, the payload_hash should be specified.
    def request(klass, method, path, payload_hash = {}, headers = {})
      auth = (self.user or self.password) ? "#{CGI.escape(user)}:#{CGI.escape(password)}@" : ''

      # If path starts with a slash, assume it is relative to the default server.
      if path[0..0] == '/'
        url = "#{klass.protocol}://#{auth}#{klass.server}#{path}"
      else
        # Otherwise, treat it as a fully qualified URL and do not modify it.
        url = path
      end

      hash = klass.attribute_formatter.encode(payload_hash)
      payload = klass.body_formatter.encode(hash)

      #logger.info "#{method.to_s.upcase} #{url} (#{payload.inspect})"

      if [:put, :post].include?(method)  # RestClient.put and .post take an extra payload argument.
        client.send(method, url, payload, request_headers.merge(headers)) do |response, request, result, &block|
          @last_response = response
          response.return!(request, result, &block)
        end
      else
        client.send(method, url, request_headers.merge(headers)) do |response, request, result, &block|
          @last_response = response
          response.return!(request, result, &block)
        end
      end
    end

    ##
    # GET a single resource.
    # 'klass' is a class that descends from WellRested::Base 
    # 'path_params_or_url' is either a url string or a hash of params to substitute into the url pattern specified in klass.path
    #    e.g. if klass.path is '/accounts/:account_id/users', then the path_params hash should include 'account_id'
    # 'query_params' is an optional hash of query parameters
    #
    # If path_params includes 'id', it will be added to the end of the path (e.g. /accounts/1/users/1)
    # If path_params_or_url is a hash, query_params will be added on the end (e.g. { :option => 'x' }) produces a url with ?option=x
    # If it is a string, query_params is ignored.
    #
    # Returns an object of class klass representing that resource.
    # If the resource is not found, raises a RestClient::ResourceNotFound exception.
    def find(klass, path_params_or_url = {}, query_params = {})
      if klass.respond_to?(:path_parameters)
        path_params_or_url = klass.path_parameters
        klass = klass.class
      end

      url = url_for(klass, path_params_or_url, query_params)
      #logger.info "GET #{url}"

      response = client.get(url, request_headers) do |response, request, result, &block|
        @last_response = response
        response.return!(request, result, &block) # default RestClient response handling (raise exceptions on errors, etc.)
      end

      raise "Invalid body formatter for #{klass.name}!" if klass.body_formatter.nil? or !klass.body_formatter.respond_to?(:decode)

      hash = klass.body_formatter.decode(response)
      decoded_hash = klass.attribute_formatter.nil? ? hash : klass.attribute_formatter.decode(hash)
      klass.new_from_api(decoded_hash)
    end

    ##
    # GET a collection of resources.
    # This works the same as find, except it expects and returns an array of resources instead of a single resource.
    def find_many(klass, path_params_or_url = {}, query_params = {})
      url = url_for(klass, path_params_or_url, query_params)

      logger.info "GET #{url}"
      response = client.get(url, request_headers) do |response, request, result, &block|
        @last_response = response
        response.return!(request, result, &block)
      end

      raise "Invalid body formatter for #{klass.name}!" if klass.body_formatter.nil? or !klass.body_formatter.respond_to?(:decode)
      array = klass.body_formatter.decode(response)

      processed_array = klass.attribute_formatter.nil? ? array : klass.attribute_formatter.decode(array)

      raise "Response did not parse to an array" unless array.is_a?(Array)

      processed_array.map { |e| klass.new_from_api(e) }
    end

    ##
    # Create the resource of klass from the given attributes.
    # The class will be instantiated, and its new_from_api and attributes_for_api methods 
    # will be used to determine which attributes actually get sent.
    # If url is specified, it overrides the default url.
    def create(klass, attributes = {}, url = nil)
      obj = klass.new(default_path_parameters.merge(attributes))

      create_or_update_resource(obj, url)
    end

    # Save a resource. 
    # Return false if doesn't pass validation.
    # If the update succeeds, return the resource.
    # Otherwise, return a hash containing whatever the server returned (usually includes an array of errors).
    def save(resource, url = nil)
      # convert any hashes that should be objects into objects before saving,
      # so that we can use their attributes_for_api methods in case they need to override what gets sent
      resource.convert_attributes_to_objects
      create_or_update_resource(resource, url)
    end

    # DELETE a resource.
    # There are two main ways to call delete.
    # 1) The first argument is a class, and the second argument is an array of path_params that resolve to a path to the resource to delete.
    #    (e.g. for klass Post with path '/users/:user_id/posts', :user_id and :id would be required in path_params_or_url to delete /users/x/posts/y)
    # 2) The first argument can be an object to delete. It should include all of the path params in its attributes.
    def delete(klass_or_object, path_params_or_url = {})
      if klass_or_object.respond_to?(:attributes_for_api) # klass_or_object is an object
        klass = klass_or_object.class
        if path_params_or_url.kind_of?(String)
          url = url_for(klass, path_params_or_url)
        else
          params = default_path_parameters.merge(klass_or_object.attributes_for_api)
          url = url_for(klass, params)
        end
      else  # klass_or_object is a class
        klass = klass_or_object
        #logger.debug "Calling delete with class #{klass.name} and params: #{path_params.inspect}"
        if path_params_or_url.kind_of?(String)
          url = url_for(klass, path_params_or_url)
        else
          params = default_path_parameters.merge(path_params_or_url)
          url = url_for(klass, params)
        end
      end

      #logger.info "DELETE #{url}"
      response = client.delete(url, request_headers) do |response, request, result, &block| 
        @last_response = response
        response.return!(request, result, &block)
      end
    end

    ##
    # Issue a PUT request to the given url.
    # The post body is specified by 'payload', which can either be a string, an object, a hash, or an array of hashes. 
    # If it is not a string, it will be recurisvely converted into JSON using any objects' attributes_for_api methods.
    # TODO: Update this to do something that makes more sense with the formatters.
    # e.g. def put(url, payload, formatter)
    def put(url, payload, options = {})
      default_options = { :json => true }
      opts = default_options.merge(options)

      payload = payload.kind_of?(String) ? payload : KeyTransformer.camelize_keys(objects_to_attributes(payload)).to_json
      response = run_update(:put, url, payload)

      if opts[:json] and !response.blank?
        objs = JSON.parse(response)
        return KeyTransformer.underscore_keys(objs)
      end

      return response
    end

    ##
    # Issue a POST request to the given url.
    # The post body is specified by 'payload', which can either be a string, an object, a hash, or an array of hashes. 
    # If it is not a string, it will be recurisvely converted into JSON using any objects' attributes_for_api methods.
    # TODO: Same issue as with put, get, etc.
    def post(url, payload, json = true)
      response = client.post(url, payload, request_headers)
      return response unless json
      parsed = JSON.parse(response)
      KeyTransformer.underscore_keys(parsed)
    end

    ##
    # Issue a GET request to the given url.
    # If json is passed as true, it will be interpreted as JSON and converted into a hash / array of hashes.
    # Otherwise, the body is returned as a string.
    # TODO: Same issue as with put. def get(url, body_formatter, attribute_formatter) ?
    def get(url, json = true)
      response = client.get(url, request_headers)
      return response unless json
      parsed = JSON.parse(response)
      KeyTransformer.underscore_keys(parsed)
    end
  
    # Generate a full URL for the class klass with the given path_params and query_params
    # In the case of an update, path params will usually be resource.attributes_for_api.
    # In the case of a find(many), query_params might be count, start, etc.
    def url_for(klass, path_params_or_url = {}, query_params = {})
      # CONSIDERATION: Defaults should be settable at the global level on the @api object.
      # They should be overrideable at the class-level (e.g. User) and again at the time of the method call.
      # url_for is currently not overrideable at the class level.
      
      auth = (self.user or self.password) ? "#{CGI.escape(user)}:#{CGI.escape(password)}@" : ''

      if path_params_or_url.kind_of?(String) 
        # if it starts with a slash, we assume its part of a 
        if path_params_or_url[0..0] == '/' 
          url = "#{klass.protocol}://#{auth}#{klass.server}#{path_params_or_url}#{klass.extension}"
        else
          # if not, we treat it as fully qualified and do not modify it
          url = path_params_or_url
        end
      else
        path = self.class.fill_path(klass.path, default_path_parameters.merge(path_params_or_url).with_indifferent_access)
        url = "#{klass.protocol}://#{auth}#{klass.server}#{path}"
      end
      url += '?' + klass.attribute_formatter.encode(query_params).to_query unless query_params.empty?
      url
    end

    # Convenience method. Also allows request_headers to be can be set on a per-instance basis.
    def request_headers
      self.class.request_headers
    end

    # Return the default headers sent with all HTTP requests.
    def self.request_headers
      # Accept necessary for fetching results by result ID, but not in most places.
      { :content_type => 'application/json', :accept => 'application/json' }
    end

    # TODO: Move this into a utility module? It can then be called from Base#fill_path or directly if needed.
    def self.fill_path(path_template, params)    
        raise "Cannot fill nil path" if path_template.nil?

        params = params.with_indifferent_access

        # substitute marked params
        path = path_template.gsub(/\:\w+/) do |match| 
          sym = match[1..-1].to_sym
          val = params.include?(sym) ? params[sym] : match
          raise ArgumentError.new "Blank parameter #{sym} in path #{path}!" if val.blank?
          val
        end

        # Raise an error if we have un-filled parameters
        if path.match(/(\:\w+)/)
          raise ArgumentError.new "Unfilled parameter in path: #{$1} (path: #{path} params: #{params.inspect})"
        end

        # ID goes on the end of the resource path but isn't spec'd there
        path += "/#{params[:id]}" unless params[:id].blank?

        path
      end
    

    protected  # internal methods follow
    
    # Create or update a resource. 
    # If an ID is set, PUT will be used, else POST.
    # If a 200 is returned, the returned attributes will be loaded into the resource, and the resource returned.
    # Otherwise, the resource will not be modified, and a hash generated from the JSON response will be returned.
    def create_or_update_resource(resource, url = nil)
      return false unless resource.valid?

      #logger.info "Creating a #{resource.class}"

      path_params = default_path_parameters.merge(resource.path_parameters)
      payload_hash = resource.class.attribute_formatter.encode(resource.attributes_for_api)
      payload = resource.class.body_formatter.encode(payload_hash)

      #logger.debug " payload: #{payload.inspect}"

      if url.nil?
        url = url_for(resource.class, path_params)  # allow default URL to be overriden by url argument  
      else
        url = url_for(resource.class, url)
      end

      # If ID is set in path parameters, do a PUT. Otherwise, do a POST.
      method = resource.path_parameters[:id].blank? ? :post : :put

      response = run_update(method, url, payload)

      hash = resource.class.body_formatter.decode(response.body)
      decoded_hash = resource.class.attribute_formatter.decode(hash)
      logger.info "* Errors: #{decoded_hash['errors'].inspect}" if decoded_hash.include?('errors')

      if response.code == 200
        # If save succeeds, replace resource's attributes with the ones returned.
        return decoded_hash.map { |hash| resource.class.new_from_api(hash) } if decoded_hash.kind_of?(Array)
        resource.load_from_api(decoded_hash)
        return resource
      elsif decoded_hash.include?('errors')
        resource.handle_errors(decoded_hash['errors'])
        return false
      end
    end

    def run_update(method, url, payload)
      logger.debug "#{method.to_s.upcase} #{url} "
      logger.debug " payload: #{payload.inspect}"

      http_status = nil
      client.send(method, url, payload, request_headers) do |response, request, result, &block|
        @last_response = response

        http_status = response.code
        case response.code
        when 400
          #logger.debug "Got 400: #{response.inspect}"
          response.return!(request, result, &block)
        when 422
          #logger.debug "Got 422: errors should be set"
          response
        else
          # default handling (raise exceptions on errors, etc.)
          response.return!(request, result, &block)
        end
      end
    end
  end
end
