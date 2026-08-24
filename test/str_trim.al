## e2e — base/str `trim` / `trim_start` / `trim_end` (ASCII-whitespace trimming, no allocation — the
## result is a `str` VIEW over the original bytes). Returns 42 iff every case is exact: both-ends trim,
## leading-only, trailing-only, an all-whitespace string (→ empty), and a no-whitespace string (unchanged).
strm := base::str
main := fn() -> u64 {
  a := strm::trim("   hello   ")     ## "hello"
  b := strm::trim_start("   xy")     ## "xy"
  c := strm::trim_end("z   ")        ## "z"
  d := strm::trim("      ")          ## "" (all whitespace)
  e := strm::trim("nows")            ## "nows" (unchanged)
  if a == "hello" and b.len == 2 and c == "z" and d.len == 0 and e == "nows" { return 42 }
  return 7
}
