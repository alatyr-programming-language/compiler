## FN-6 — an inline function VALUE `fn(sig) { body }` in expression position (grammar `fn-value ::=
## fn-sig block`). A NON-CAPTURING lambda lowers to a code pointer (§1.2): the driver lifts it to a
## synthetic top-level fn `<mod>__lam<fnpos>` and rewrites the expression to a code-pointer `FnRef`;
## calling it goes through the existing indirect-call path. `inc(41) = 42`. Also exercises a lambda
## passed to a higher-order fn (`apply`).
apply := fn(g : u64, x : u64) -> u64 { return g(x) }
main := fn() -> u64 {
  inc := fn(n : u64) -> u64 { return n + 1 }
  return apply(inc, 41)
}
