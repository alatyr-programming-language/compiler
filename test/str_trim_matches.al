## e2e — base::str trim_matches / trim_start_matches / trim_end_matches: strip a SPECIFIC byte from
## both / the start / the end (allocation-free str views), for peeling quotes / brackets / padding.
## Returns 42 iff all exact.
sm := base::str

main := fn() -> u64 {
  a := sm::trim_matches("\"quoted\"", 34)          ## strip surrounding " (34) -> "quoted"
  if not (a == "quoted") { return 1 }
  b := sm::trim_start_matches("xxdata", 120)        ## strip leading 'x' -> "data"
  if not (b == "data") { return 2 }
  c := sm::trim_end_matches("value000", 48)         ## strip trailing '0' -> "value"
  if not (c == "value") { return 3 }
  d := sm::trim_matches("nomatch", 122)             ## no 'z' -> unchanged
  if not (d == "nomatch") { return 4 }
  e := sm::trim_matches("----", 45)                 ## all '-' -> empty
  if e.len != 0 { return 5 }
  return 42
}
