
module WellRested
  class JSONFormatter
    def encode(obj)
      obj.to_json
    end

    def decode(serialized_representation)
      JSON.parse(serialized_representation)
    end
  end
end
