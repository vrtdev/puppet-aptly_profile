module Puppet
  module Parser
    # Puppet functions namespace
    module Functions
      newfunction(
        :find_key,
        type: :rvalue,
        doc: <<-'ENDHEREDOC') do |args|

            Recursivly searches a hash for a key.

            If a key has been found, the value of the matching key will be returned.
            If the key can not be found, nil is returned.

          ENDHEREDOC

          unless args.length == 2
            raise Puppet::ParseError, "find_key(): Wrong number of arguments (#{args.length}; must be = 2)"
          end

          hash = args[0]
          key = args[1]

          unless hash.is_a?(Hash)
            raise Puppet::ParseError, "find_key(): Unexpected argument type #{hash.class}. Must be a hash."
          end

          return hash[key] if hash.key?(key)
          hash.each do |_k, v|
            return function_find_key([v, key]) if v.is_a?(Hash)
          end
          return nil
        end
    end
  end
end
