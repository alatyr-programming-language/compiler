## e2e build_reject — a DIRECT `match recv.map(f) { … }` (unbound call scrutinee) whose mapper produces
## a MULTI-WORD (struct) payload. The direct call-scrutinee staging sizes the scratch from the RAW
## param-generic return span (payload = 1 word), which would TRUNCATE the 2-word `Pt` payload to its
## word 0 — a silent miscompile. The lower FAILS LOUD instead (a `selfhost:` panic pointing to the
## bind-to-local workaround). The BOUND form (`om := recv.map(f); match om`) works — see
## option_map_ufcs_struct.al. Scalar-payload direct matches (result_map_ufcs / option_map_ufcs) keep
## compiling + running.
Pt := struct { x : u64, y : u64 }
mk := fn(v : u64) -> Pt { return Pt(x = 40, y = 2) }

main := fn() -> u64 {
  o : Option(u64) = Option.Some(1)
  return match o.map(mk) { Option::Some(p) => p.x + p.y; Option::None => 7 }
}
