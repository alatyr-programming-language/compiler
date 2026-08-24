## e2e — `Option::map` via implicit UFCS producing a MULTI-WORD (struct) payload, BOUND then matched
## (`om := o.map(mk); match om`). Exercises the full generic-enum-return substitution on the result
## binding (`collect_slots` → `subst_enum_ret_span` recovers `U = Pt` from the fn ARGUMENT's return, so
## `om` is sized as `Option(Pt)` = disc + 2 payload words, not truncated). The DIRECT (unbound) form of
## this is fail-loud (see reject_map_ufcs_direct_struct.al); the bound form is the supported idiom.
## Returns 42.
Pt := struct { x : u64, y : u64 }
mk := fn(v : u64) -> Pt { return Pt(x = 40, y = 2) }

main := fn() -> u64 {
  o : Option(u64) = Option.Some(1)
  om := o.map(mk)
  match om { Option::Some(p) => { return p.x + p.y } Option::None => { return 7 } }
}
