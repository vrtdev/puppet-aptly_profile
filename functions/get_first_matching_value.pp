function aptly_profile::get_first_matching_value(
  Variant[Undef, Hash, Enum['']] $source = {},
  Variant[Undef, Hash, Enum['']] $criteria = {},
  Boolean $strict = false,
) >> Optional[Hash] {

  # Don't even bother if the source is empty, So will the result be.
  if empty($source) {
    $result = undef
  }
  # Criteria is empty. Strict => return nil. Otherwise, return first element.
  elsif empty($criteria) {
    $result = $strict ? {
      true    => undef,
      default => values($source)[0]
    }
  }
  else {
    $matching = $source.filter |$_key, $source_value| {
      # Loop each criteria.
      $criteria_matches = $criteria.map |$criteria_key, $criteria_value| {
        $criteria_value == $source_value[$criteria_key]
      }
      # No false matches in criteria? All good!
      ! (false in $criteria_matches)
    }
    if empty($matching) {
      $result = undef
    }
    else {
      $result = values($matching)[0]
    }
  }
  $result
}
