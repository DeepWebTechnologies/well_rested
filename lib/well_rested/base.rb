# encoding: utf-8

require 'active_model'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'

require 'well_rested/json_formatter'
require 'well_rested/camel_case_formatter'
require 'well_rested/utils'

module WellRested
  class Base
    include Utils
    include WellRested::Utils

    include ActiveModel::Validations
    include ActiveModel::Serializers::JSON

    class_attribute :protocol
    class_attribute :server
    class_attribute :path
    class_attribute :schema

    class_attribute :body_formatter
    class_attribute :attribute_formatter
    class_attribute :extension   # e.g. .json, .xml

    # class-level defaults
    self.protocol = 'http'
    # a body formatter must respond to the methods encode(hash_or_array) => string and decode(string) => hash_or_array
    self.body_formatter = JSONFormatter.new   
    self.extension = ''
    # an attribute formatter must respond to encode(attribute_name_string) => string and decode(attribute_name_string) => string
    self.attribute_formatter = CamelCaseFormatter.new

    attr_reader :attributes
    attr_accessor :new_record

    ##
    # Define the schema for this resource.
    #
    # Either takes an array, or a list of arguments which we treat as an array.
    # Each element of the array should be either a symbol or a hash. 
    # If it's a symbol, we create an attribute using the symol as the name and with a null default value.
    # If it's a hash, we use the keys as attribute names.
    #   - Any values that are hashes, we use to specify further options (currently, the only option is :default).
    #   - Any value that is not a hash is treated as a default. 
    #  e.g.
    #  define_schema :x, :y, :z                            # x, y, and z all default to nil
    #  define_schema :id, :name => 'John'                  # id defaults to nil, name defaults to 'John'
    #  define_schema :id, :name => { :default => 'John' }  # same as above
    def self.define_schema(*args)
      return schema if args.empty?

      attrs = args.first.is_a?(Array) ? args.first : args
      self.schema = {}.with_indifferent_access
      attrs.each do |attr|
        if attr.is_a?(Symbol)
          self.schema[attr] = { :default => nil }
        elsif attr.is_a?(Hash)
          attr.each do |k,v|
            if v.is_a?(Hash)
              self.schema[k] = v
            else
              self.schema[k] = { :default => v }
            end
          end
        end
      end

=begin
      # Possible alternative to using method_missing:
      # define getter/setter methods for attributes.
      @attributes.keys.each do |attr_name|
        define_method(attr_name) { @attributes[attr_name] }
        define_method("#{attr_name}=") { |val| @attributes[attr_name] = val }
      end
=end

      self.schema
    end

    def initialize(attrs = {})
      raise "Attrs must be hash" unless attrs.is_a? Hash

      self.load(attrs, false) 
    end

    # Define an actual method for ID. This is important in Ruby 1.8 where the object_id method is also aliased to id.
    def id
      attributes[:id]
    end

    # borrowed from http://stackoverflow.com/questions/2393697/look-up-all-descendants-of-a-class-in-ruby
    # Show all subclasses
    def self.descendants
      ObjectSpace.each_object(::Class).select { |klass| klass < self }
    end

    # Create a map of all descendants of Base to lookup classes from names when converting hashes to objects.
    def self.descendant_map
      return @descendant_map if @descendant_map
      @descendant_map = {}.with_indifferent_access
      self.descendants.each do |des|
        unless des.name.blank?
          sep_index = des.name.rindex('::')
          short_name = sep_index ? des.name[sep_index+2..-1] : des.name
          @descendant_map[short_name] = des
        end
      end
      @descendant_map
    end

    # Convenience method for creating an object and calling load_from_api
    # The API should call this method when creating representations of objects that are already persisted.
    #
    # By default, attributes loaded from the API have new_record set to true. This has implications for Rails form handling.
    # (Rails uses POST for records that it thinks are new, but PUT for records that it thinks are already persisted.)
    def self.new_from_api(attrs)
      obj = self.new
      obj.load_from_api(attrs)
      return obj
    end

    # Load this resource from attributes. If these attributes were received from the API, true should be passed for from_api.
    # This will ensure any object-specific loading behavior is respected.
    # example:
    #   res = Resource.new
    #   res.load(:name => 'New')
    def load(attrs_to_load, from_api = false)
      raise "Attrs is not a hash: #{attrs_to_load.inspect}" unless attrs_to_load.kind_of? Hash

      #puts "*** Warning: loading a resource without a schema (#{self.class})!" if schema.nil?
      #raise "Tried to load attributes for a resource with no schema (#{self.class})!" if schema.nil?
      
      # By default we mark a record as new if it doesn't come from the API and it doesn't have an ID attribute.
      self.new_record = !from_api and !attrs_to_load.include?('id')

      new_attrs = {}.with_indifferent_access

      # Take default values from schema, but allow arbitrary args to be loaded.
      # We will address the security issue by filtering in attributes_for_api.
      schema.each { |key, opts| new_attrs[key] = opts[:default] } unless schema.blank?
      new_attrs.merge!(attrs_to_load)

      @attributes = self.class.hash_to_objects(new_attrs, from_api).with_indifferent_access

      return self
    end

    # Load attributes from the API.
    # This method exists to be overridden so that attributes created manually can be handled differently from those loaded from the API.
    def load_from_api(attrs)
      load(attrs, true)
    end

    # Convert attribute hashes that represent objects into objects
    def convert_attributes_to_objects
      self.class.hash_to_objects(attributes, self.class)
    end

    # This method is called by API when a hash including 'errors' is returned along with an HTTP error code.
    def handle_errors(received_errors)
      received_errors.each do |err|
        self.errors.add :base, err
      end
    end

    # When we are loading a resource from an API call, we will use this method to instantiate classes based on attribute names.
    def self.find_resource_class(class_name)
      klass = Utils.get_class(class_name)
      #puts "**** descendant map: #{Base.descendant_map.inspect}"
      return klass if klass.respond_to?(:new_from_api)
      Base.descendant_map[class_name]
    end

    # Convert a hash received from the API into an object or array of objects.
    # e.g. Base.hash_to_objects({'base' => {'name' => 'Test'} }) => {"base"=>#<WellRested::Base:0x10244de70 @attributes={"name"=>"Test"}}
    def self.hash_to_objects(hash, from_api = false)
      hash.each do |k,v|
        if v.kind_of?(Hash)
          class_name = k.camelize
          klass = self.find_resource_class(class_name)
          if klass
            hash[k] = from_api ? klass.new_from_api(v) : klass.new(v)
          end
        elsif v.kind_of?(Array)
          class_name = k.to_s.singularize.camelize
          #puts "**** class_name=#{class_name}"
          klass = find_resource_class(class_name)
          if klass
            #puts "**** class exists, instantiation"
            hash[k] = v.map do |o| 
              if o.kind_of?(Hash) 
                from_api ? klass.new_from_api(o) : klass.new(o) 
              else
                o
              end
            end
          else
            #puts "**** class does not exist"
          end
        end
      end
      hash
    end

    def self.fill_path(params)
      API.fill_path(self.path, params)
    end

    # Return the attributes that we want to send to the server when this resource is saved.
    # If a schema is defined, only return elements defined in the schema.
    # Override this for special attribute-handling.
    def attributes_for_api
      # by default, filter out nil elements
      hash = objects_to_attributes(@attributes.reject { |k,v| v.nil? }.with_indifferent_access)
      # and anything not included in the schema
      hash.reject! { |k,v| !schema.include?(k) } unless schema.nil?
      hash
    end

    # API should use these to generate the path. 
    # Override this to control how path variables get inserted.
    def path_parameters
      objects_to_attributes(@attributes.reject { |k,v| v.nil? }.with_indifferent_access)
    end

    # Run active_model validations on @attributes hash.
    def read_attribute_for_validation(key)
      @attributes[key]
    end

    # Return a string form of this object for rails to use in routes.
    def to_param
      self.id.nil? ? nil : self.id.to_s
    end
    
    # Return a key for rails to use for... not sure exaclty what.
    # Should be an array, or nil.
    def to_key
      self.id.nil? ? nil : [self.id] 
    end

    # The following 3 methods were copied from active_record/persistence.rb
    # Returns true if this object hasn't been saved yet -- that is, a record
    # for the object doesn't exist in the data store yet; otherwise, returns false.
    def new_record?
      self.new_record
    end

    # Alias of new_record? Apparently used by Rails sometimes.
    def new?
      self.new_record
    end

    # Returns true if this object has been destroyed, otherwise returns false.
    #def destroyed?
    #  @destroyed
    #end

    # Returns if the record is persisted, i.e. it's not a new record and it was
    # not destroyed.
    def persisted?
    #  !(new_record? || destroyed?)
      !new_record?
    end

    # Equality is defined as having the same attributes.
    def ==(other)
      other.respond_to?(:attributes) ? (self.attributes == other.attributes) : false
    end

    # Respond to getter and setter methods for attributes.
    def method_missing(method_sym, *args, &block)
      method = method_sym.to_s
      # Is this an attribute getter?
      if args.empty? and attributes.include?(method)
        attributes[method]
      # Is it an attribute setter?
      elsif args.length == 1 and method[method.length-1..method.length-1] == '=' and attributes.include?(attr_name = method[0..method.length-2])
        attributes[attr_name] = args.first
      else
        super
      end
    end
  end
end

