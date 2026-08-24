## Store-escape (spec Memory §5.3.1) hidden inside an `if` branch — the walker recurses into nested
## control-flow blocks, so `G = ptr(x)` under a conditional is caught too. Check must reject (rc 1).
SENTINEL := 0
mut G := ptr(SENTINEL)
leak := fn(c : bool) {
  x := 5
  if c {
    G = ptr(x)
  }
}
main := fn() -> u64 { 0 }
