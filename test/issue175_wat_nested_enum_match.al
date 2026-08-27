## Failure-first: the parent compiler emits a valid WAT module, but it returns the caller's 7
## instead of the matched payload. The caller-value check is independent: caller_value must stay 7.
## The inner A(pa) must shadow the outer pa (9), while inner B(_) must carry outer pa (42).
## x86_64 is the control result; this fixture is registered as a plain run so the other backends
## are checked by the cross-target sweeps, and as run_wat for the WAT execution path.
E := enum { A(u64), B(u64) }

read_payload := fn(in out caller_value : u64, outer : E, inner : E) -> u64 {
  match outer {
    E.A(pa) => {
      match inner {
        E.A(pa) => { return pa }
        E.B(_) => { return pa }
      }
    }
    E.B(_) => { return 0 }
  }
  return 0
}

main := fn() -> u64 {
  mut caller_value : u64 = 7
  shadowed := read_payload(caller_value, E.A(42), E.A(9))
  carried := read_payload(caller_value, E.A(42), E.B(0))
  if caller_value != 7 { return 1 }
  if shadowed != 9 { return 2 }
  return carried
}
