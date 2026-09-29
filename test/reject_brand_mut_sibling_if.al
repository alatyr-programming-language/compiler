## e2e — Issue #583 slice 7a / Types §5.4. Two SIBLING brands over one block share nothing, so an `if`
## whose two branches are a local of each cannot have one type. The direct-branch guard in `check`
## already refuses it for two plain locals; it read each local's RAW tag byte, where a `mut` binding
## carries the `+128` storage flag, so a `mut` brand local (byte 136) never counted as a brand there and
## the same crossing compiled clean. Both locals are `mut` here on purpose: that is the shape the guard
## missed. The same program with plain `a` and `b` was already refused and is not what this witnesses.
##
## Failure-first: on the parent compiler this program passed `check`, built, and ran to 1.
A := brand(u64)
B := brand(u64)

main := fn() -> u64 {
  mut a : A = A(1)
  mut b : B = B(2)
  c : A = if true { a } else { b }
  return u64(c)
}
