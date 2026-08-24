## e2e — `fmt` on the STATEMENT spelling of a chained alternative, in the shape the compiler's own
## largest modules are written in: a three-way chain whose arms are single void CALLS, followed by
## another statement so the chain cannot be a block's tail value. `fmt` used to re-brace such a
## chain one level per alternative; the nested form puts the inner branch LAST in a block, where
## the parser reclassifies it as a value-if, so pass 2 rendered it on one line and pass 1 did
## not — `fmt(fmt(x)) != fmt(x)` on driver, sema, wat and three of the lower's files. Three
## instances, one per arm, each with its own accumulator and its own selector, so a chain that
## bound the wrong condition to the wrong arm cannot reach 42; the first disagreement returns its
## own code (100..102, each under wasm's 126 ceiling). The selector comes back from a call so the
## chain is not constant-folded away, and the accumulator is addressed where it lives rather than
## being forwarded through a second call: forwarding a `ptr(mut T)` parameter into a further call
## loses the store on aarch64 and riscv64, which would have made this fixture disagree across
## backends for a reason that has nothing to do with formatting.
selector := fn(x : u64) -> u64 {
  return x
}

bump := fn(p : ptr(mut u64), by : u64) {
  deref(p) = deref(p) + by
}

main := fn() -> u64 {
  mut a : u64 = 0
  ka := selector(0)
  if ka == 0 { bump(ptr(mut a), 1) }
  else if ka == 1 { bump(ptr(mut a), 10) }
  else { bump(ptr(mut a), 100) }
  bump(ptr(mut a), 1000)
  if a != 1001 { return 100 }
  mut b : u64 = 0
  kb := selector(1)
  if kb == 0 { bump(ptr(mut b), 1) }
  else if kb == 1 { bump(ptr(mut b), 10) }
  else { bump(ptr(mut b), 100) }
  bump(ptr(mut b), 1000)
  if b != 1010 { return 101 }
  mut c : u64 = 0
  kc := selector(7)
  if kc == 0 { bump(ptr(mut c), 1) }
  else if kc == 1 { bump(ptr(mut c), 10) }
  else { bump(ptr(mut c), 100) }
  bump(ptr(mut c), 1000)
  if c != 1100 { return 102 }
  return 42
}
