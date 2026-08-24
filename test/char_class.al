## e2e — base::char classification + folding, now reachable (the predicates existed but were not `pub`).
## A `char` is a Unicode code point (u32-shaped); build one with `char(n)`. Exercises is_digit/is_alpha/
## is_alnum/is_whitespace/is_hex_digit, to_lower/to_upper (ASCII fold), and hex_value (Option(u32)).
## Returns 42 iff all exact.
ch := base::char

main := fn() -> u64 {
  if not ch::is_digit(char(53)) { return 1 }          ## '5'
  if ch::is_digit(char(97)) { return 2 }              ## 'a' not a digit
  if not ch::is_alpha(char(97)) { return 3 }          ## 'a'
  if not ch::is_alnum(char(48)) { return 4 }          ## '0'
  if not ch::is_whitespace(char(32)) { return 5 }     ## space
  if not ch::is_hex_digit(char(102)) { return 6 }     ## 'f'
  if ch::is_hex_digit(char(103)) { return 7 }         ## 'g' not hex
  if u32(ch::to_lower(char(65))) != 97 { return 8 }   ## 'A' -> 'a'
  if u32(ch::to_upper(char(97))) != 65 { return 9 }   ## 'a' -> 'A'
  hv := ch::hex_value(char(97))                        ## 'a' -> 10
  match hv {
    Option::Some(v) => { if v != 10 { return 10 } }
    Option::None => { return 10 }
  }
  return 42
}
