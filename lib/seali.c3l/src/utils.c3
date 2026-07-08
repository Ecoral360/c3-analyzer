module seali::utils;

macro @expand_val(String $val) @const {
  $expand(@sprintf("return %s;", $val));
}

macro bool @is_lower($c) @const => $c >= 'a' &&& $c <= 'z';
