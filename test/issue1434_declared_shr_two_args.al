## #1434 — the same silent wrong value at `shr`, the second name the IR builder hijacked by text.
## NON-VACUOUS on the parent 48ecfed4 (native x86_64, tree Stage1): `alatyr build` **succeeds** and the
## program answers **34** where 42 is due (`sarq` on the operand: 10 >> 2 = 2, + 32 = 34), with no
## diagnostic and no `call …__shr` in the emitted assembly. The identical program with the callee spelled
## `shrx` answers 42 there, and the same shape under `rotl` already answered 42 on the parent because
## `ib_bx_shift` refuses rotations and they fall through to the user call — which is why only `shl` and
## `shr` were hijacked. A declared name is a call to that declaration (Grammar §2.3, Declarations §6.1),
## so this is 10 + 32.
shr := fn(a : u64, b : u64) -> u64 { a }
main := fn() -> u64 {
  shr(10, 2) + 32
}
## expect: run 42
