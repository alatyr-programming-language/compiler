## e2e — per-signature OVERLOAD MANGLING (§1.4-A-5 deeper). Two non-generic `add` fns share a name
## but differ in parameter type (u64 vs i64). Before, both mangled to one `main__add` label → the
## assembler rejected the duplicate symbol AND a call dispatched to the wrong (first-emitted) body.
## Now each definition gets a per-signature suffix from its first parameter's type (`add__u64` /
## `add__i64`), and each CALL recovers its target from the first argument whose type it can infer
## (here the value PARAMS `p`/`q`, recorded on their slots) — so `usum` reaches `add__u64` and `isum`
## reaches `add__i64`. 20+20 = 40 (u64) and (-5)+(-5) = -10 (i64); 40 + (-10 + 12) = 42.
add := fn(a : u64, b : u64) -> u64 { return a + b }
add := fn(a : i64, b : i64) -> i64 { return a + b }
usum := fn(p : u64, q : u64) -> u64 { return add(p, q) }
isum := fn(p : i64, q : i64) -> i64 { return add(p, q) }
main := fn() -> u64 {
  r1 := usum(20, 20)
  r2 := isum(0 - 5, 0 - 5)
  return r1 + unchecked bitcast(u64, r2 + 12)
}
