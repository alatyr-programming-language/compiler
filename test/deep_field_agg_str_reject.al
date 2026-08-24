## build_reject — a deep-chain STR final field whole-assign (`o.mid.name = "hello"`) must FAIL LOUD.
## Like the enum case, the nested str FINAL-field access is unsupported END-TO-END — even the READ
## (`o.mid.name.len()`) is not lowered — so a whole-assign can only produce garbage; the compiler
## refuses it loudly rather than emit a silent word-0-only store. Flatten to a single hop or bind the
## inner struct to a local. (The single-hop str field write `g.name = "…"` works.)
Mid := struct { name : str, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(name = "xx", x = 0), tag = 7)
  o.mid.name = "hello"
  return u64(o.mid.name.len() + 37)
}
