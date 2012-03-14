require 'generic_utils'

module WellRested
  module Utils
    extend GenericUtils
    extend self

    # Turn any nested resources back into hashes before sending them
    def objects_to_attributes(obj)
      if obj.respond_to?(:attributes_for_api)
        obj.attributes_for_api
      elsif obj.kind_of?(Hash)
        new_attributes = {}.with_indifferent_access
        obj.each do |k, v|
          new_attributes[k] = objects_to_attributes(v)
        end
        new_attributes
      elsif obj.kind_of?(Array)
        obj.map { |e| self.objects_to_attributes(e) }
      else
        obj
        #raise "Attributes was not a Hash or Enumerable"
      end
    end
  end
end
