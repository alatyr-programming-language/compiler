## #1406 — the third arm of the same misroute: `emit_gas` matched the callee TEXT `sub` before the
## generic call, so a declared `sub` used in VALUE position was refused as a str/view expression even
## though it returns a scalar. NON-VACUOUS on the parent c00eae90 (x86_64): `alatyr build` exits 1 with
## "live str/view expression has no lowering path"; the identical program with the callee spelled `take`
## answers 42 there. A declared name is a call to that declaration (Grammar §2.3: `sub` is not a
## keyword; Declarations §6.1: the inner declaration wins), so this is 10 + 32.
sub := fn(a : u64) -> u64 { a }
main := fn() -> u64 {
  u64(sub(10)) + 32
}
## expect: run 42
