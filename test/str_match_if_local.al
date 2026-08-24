## e2e (aggregate/str-valued match/if bound to a LOCAL). `s := match n { … => "a" }` / `p := if c {
## P(…) } else { … }` sized the local as a scalar and stored one word, so a wider value (str {ptr,len},
## struct, enum, tuple) was truncated — aggregates/strs don't materialize on the stack in bare
## expression position. Now `match_if_agg_kind` classifies the RHS (struct/enum/tuple/str),
## collect_slots sizes the local accordingly, and `emit_val_match_to_local`/`emit_val_if_to_local`
## deliver each arm/branch's value into the local's slots (per-arm struct/enum/array assign or a str
## {ptr,len} pop) — the local-binding dual of the return-value delivery via match/if.
P := struct { a : u64, b : u64 }
E := enum { Some(u64), None }
main := fn() -> u64 {
  n : u64 = 0
  s := match n { 0 => "hello", _ => "x" }        ## str via match: "hello" (len 5)
  c : bool = false
  t := if c { "hi" } else { "world!" }            ## str via if: "world!" (len 6)
  p := match n { 0 => P(a = 20, b = 2), _ => P(a = 0, b = 0) }   ## struct via match: (20,2)
  e := if c { E.None } else { E.Some(4) }         ## enum via if: Some(4)
  tu := match n { 0 => (3, 2), _ => (0, 0) }      ## tuple via match: (3,2)
  ev := match e { E::Some(x) => x, E::None => 0 } ## 4
  ## 5 + 6 + (20+2) + 4 + (3+2) = 42
  s.len + t.len + p.a + p.b + ev + tu.0 + tu.1
}
