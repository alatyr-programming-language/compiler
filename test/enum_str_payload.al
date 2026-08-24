## e2e (§4 layout — a `str` PAYLOAD of an enum variant). A `str` is a 2-word `{ptr, len}` (Memory
## §3.5), so a `str`-payload variant occupies 2 payload words: `enum_max_arity` counts it as 2, the
## construction `E.Named("…")` stores {ptr, len} (via emit_str_assign), and a `match { Named(s) => …}`
## binds `s` as a 2-word str (ek 4) aliased to the payload slots, so `s.len` reads the second word.
## Exercises a STATEMENT match (block arms) and an EXPRESSION match (value arms), plus a sibling
## variant with a SCALAR payload so the discriminant/payload layout is shared. `src/`+`lib/` enums use
## `usize` spans (never a `str` payload), so this stays fixpoint-neutral.
E := enum { Named(str), Numbered(u64), Anon }

name_len := fn(e : E) -> u64 {
  match e {
    Named(s) => { return s.len }        ## str payload — s.len reads the 2nd payload word
    Numbered(k) => { return k }
    Anon => { return 0 }
  }
}

main := fn() -> u64 {
  a := name_len(E.Named("hello"))                 ## 5
  b := name_len(E.Numbered(30))                   ## 30
  ## expression-position match binding a str payload
  e := E.Named("hi")
  c := match e { Named(s) => s.len, Numbered(k) => k, Anon => 0 }   ## 2
  d := name_len(E.Anon)                           ## 0
  a + b + c + d + 5                               ## 5 + 30 + 2 + 0 + 5 = 42
}
