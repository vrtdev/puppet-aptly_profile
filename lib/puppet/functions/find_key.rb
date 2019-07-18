# Find a key in a nested hash structure and return its value.
#
# This function will scan nested hashes until a matching key
# has been found and return its value or it will return nil if
# the key is not found anywhere.
#
Puppet::Functions.create_function(:find_key) do
  # @param hash The hash structure(s) to search in.
  # @param key  The key you are looking for.
  # @return The value for the found key or `nil`.
  dispatch :find_key do
    param 'Hash', :hash
    param 'String', :key
  end

  def find_key(hash, key)
    find_key_in_hash(hash, key)
  end

  private

  # Looks for the key and returns whatever value that is found.
  def find_key_in_hash(hash, key, nesting = false)
    return hash[key] if hash.key?(key)

    found_nested = NotFound.new
    hash.each do |_k, v|
      found_nested = find_key_in_hash(v, key, true) if v.is_a?(Hash)
      return found_nested unless found_nested.is_a?(NotFound)
    end

    return NotFound.new if nesting
    nil
  end

  class NotFound
    # dummy class to allow us to use nil values.
  end
end
