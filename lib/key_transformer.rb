
# This module is used to transform the keys found in resources between Rail's native underscore_case 
# and the camelCase typically found in Java, etc.

module KeyTransformer
  extend self

  # Run through a hash or array of hashes and replace the keys with underscored versions.
  # NOTE: Hash values may include simple values, other hashes or arrays, but Arrays may only include hashes.
  # If we had an array of symbols (e.g. for permissions), we'd have to do this slightly differently
  def underscore_keys(hash_or_array)
    key_transform = Proc.new { |key| key.to_s.underscore }
    transform_keys(hash_or_array, key_transform)
  end

  def camelize_keys(hash_or_array, upper_or_lower = :lower)
    key_transform = Proc.new { |key| key.to_s.camelize(upper_or_lower) }
    transform_keys(hash_or_array, key_transform)
  end
  
  # Takes a hash or array to process and a key transform (Proc),
  # which should accept a key and return a transformed key.
  # Returns a hash or array, depending on which was passed.
  # NOTE: any objects which respond to 'attributes' (active record, active resource) will be turned into hashes.
  # NOTE: all hashes are returned with indifferent access
  def transform_keys(hash_or_array, key_transform)
    if hash_or_array.is_a? Array
      hash_or_array.map { |obj| transform_keys(obj, key_transform) }
    elsif hash_or_array.is_a? Hash
      new_hash = {}.with_indifferent_access
      hash_or_array.each do |key, val|
        new_hash[key_transform.call(key)] = transform_keys(val, key_transform) 
      end
      new_hash
    # Note: this case has been disabled because we now convert objects to hashes before passing them into underscore/camelize_keys.
    # elsif hash_or_array.respond_to? :attributes    # if this is an object rather than a hash / array, get the hash from its attributes
    #  transform_keys(hash_or_array.attributes, key_transform)
    else
      hash_or_array
    end
  end
end

