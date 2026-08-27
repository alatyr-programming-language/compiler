## e2e — an enum payload binding may shadow an outer `in out` parameter with the same spelling.
## The match-arm binding must win over the caller place. Before the backend context fix, the binding load
## was followed by an unconditional `in out` parameter load, so this returned the caller's stale value (7)
## instead of the payload (42). This is a silent-miscompile guard for both AArch64 and RV64; the nested
## outer-binding path is covered by comptime_enum_eq.al.
E := enum { A(u64), B(u64) }

read_payload := fn(in out pa : u64, e : E) -> u64 {
  match e {
    E.A(pa) => { return pa }
    E.B(_) => { return 0 }
  }
  return 0
}

main := fn() -> u64 {
  mut caller_value : u64 = 7
  return read_payload(caller_value, E.A(42))
}
