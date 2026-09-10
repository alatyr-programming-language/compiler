## e2e — Issue #299 / Types §4.2-§4.3. Reading a branded struct field yields a value of that brand,
## and `fld : u64 = s.x` is therefore the B1R direction of §4.2's brand class — brand to the type it
## brands — which §4.2 makes EXPLICIT (`u64(s.x)`), never implicit.
##
## The refusal PR #593 landed recovered a value's brand identity from three sources: a constructor
## `A(v)`, an unambiguous declared callee result, and an annotated local or parameter. A `Field`
## expression was none of the three, so `s.x` had no identity, and the poison-tolerant sink accepted
## it. A field's declared type is written down in its own struct declaration, so it is as reliable a
## source as an annotated local; this fixture is the witness that it is now read.
##
## Four-backend witness: the rule is decided in `check` and is TARGET-INDEPENDENT, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row for this source and each must be a
## refusal, not only the x86 one.
##
## Failure-first: on the parent compiler (`main` b61bfa4) this program checked at rc 0, built at
## rc 0 and RAN TO 4.
A := brand(u64)

S := struct { x : A }

main := fn() -> u64 {
  s := S(x = A(4))
  fld : u64 = s.x
  return fld
}
