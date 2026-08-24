## e2e — a `str` payload in a GENERIC enum instance (`Option(str)`). The str is a 2-word {ptr,len}
## value; the enum-payload construction used to emit only word 0 (the ptr) into the payload register, so
## `Option(str).Some(s)` truncated the len (a match-bound `r` came back with len 0). Now payload_agg_words
## counts a str payload as 2 words and emit_enum_value pushes its {ptr,len} into both payload registers.
## Covers a str-VAR payload, a str-LITERAL payload, and the None arm. Returns 42 iff all exact.
mk := fn(s : str, some : bool) -> Option(str) {
  if some { Option(str).Some(s) } else { Option(str).None }
}

main := fn() -> u64 {
  a := mk("hello", true)
  match a {
    Option::Some(r) => { if not (r == "hello") { return 1 } }
    Option::None => { return 1 }
  }
  b := mk("x", false)
  match b {
    Option::Some(r) => { return 2 }
    Option::None => {}
  }
  c := Option(str).Some("world")           ## str-literal payload, constructed inline
  match c {
    Option::Some(r) => { if not (r == "world") { return 3 } if r.len != 5 { return 4 } }
    Option::None => { return 3 }
  }
  return 42
}
