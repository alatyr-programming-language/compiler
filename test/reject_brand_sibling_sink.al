## e2e — Issue #299 / Types §5.4:395-400. Two SIBLING brands over one block do not convert into each
## other at all, so passing a `B` where an `A` is declared is an ill-formed program. That is a
## TARGET-INDEPENDENT rule decided in `check`, and this is the tracked-corpus witness that all four
## backends refuse it rather than only x86: the per-file manifest carries an x86_64, aarch64,
## riscv64 and wasm row for this source, and each must be a refusal.
##
## The value is built with `A(1)` / `B(2)` on purpose. Written the way #299's own table wrote it
## (`b : B = 2`, an annotated integer literal) five of its six rows come back refused for a DIFFERENT
## reason — #563, which fires before the sink is ever judged and masks it — so a fixture written that
## way would prove nothing about brand identity.
##
## Failure-first: on the parent compiler this program compiled clean and ran to 7.
A := brand(u64)
B := brand(u64)

take_a := fn(x : A) -> u64 { u64(x) }

main := fn() -> u64 {
  b : B = B(2)
  return take_a(b)
}
