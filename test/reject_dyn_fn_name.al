## e2e REJECT (FN-11, Functions §1.6) — a `dyn fn(T…)->R` binding is the type-erased two-word
## {code, env} fat pair, and the ONLY construction form the spec admits is `dyn_over(ptr(mut <store>))`
## over a NAMED PLACE holding a static closure (the environment is explicit storage the `dyn` borrows —
## I3). Binding a `dyn` type DIRECTLY to a plain fn NAME supplies no environment place at all: it is the
## ZERO-CAPTURE case, which the thin function-value type `fn(u64) -> u64` (FN-10) already covers.
##
## Left unchecked the lower's fat-pair emit went looking for a `dyn_over` store slot that does not exist,
## read a bogus lambda index out of the decl vector and the COMPILER SIGSEGV'd (exit 139) — an
## uncontrolled hardware fault on ordinary user source. It is now a LOCATED front-end reject
## (`alatyr: check: type mismatch at line <the binding>`), so `check` returns 1 and the build fails loud.
mkd := fn(x : u64) -> u64 { return x + 1 }

main := fn() -> u64 {
  d : dyn fn(u64) -> u64 = mkd
  return d(41)
}
