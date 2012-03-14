module WellRested
  class CamelCaseFormatter
    def initialize(lower = true)
      raise "Upper case camelizing not supported yet" unless lower   # TODO: Support upper-camel-casing
    end

    def encode(hash)
      KeyTransformer.camelize_keys(hash)
    end

    def decode(hash)
      KeyTransformer.underscore_keys(hash)
    end
  end
end
