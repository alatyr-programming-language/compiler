## e2e — issue #448 CONTROL. The spellings aarch64 and riscv64 cannot lower must STAY fail-loud while the
## enum-place store is fixed: a refusal that quietly became a wildcard would be the very defect #448 is
## about, in the other direction.
##
## `x := h.t` binds a field to a local the backends cannot resolve to an enum, so the `match` reaches
## `brk #0 // unsupported match` / `ebreak` and the program traps. Registered `run_a64`/`run_rv64` at 133
## (128 + SIGTRAP), not merely "nonzero": a wildcard that slipped into a nonzero arm would satisfy a
## nonzero-exit assertion and prove nothing. x86_64 lowers all of it and answers 42.
##
## Measured with the cross binutils under qemu. Parent 5eb6739 and this tree agree: x86_64 42,
## aarch64 133, riscv64 133. wasm traps too (134).
Tag := enum { Red, Green, Blue }
Holder := struct { t : Tag }

## the enum LOCAL spelling: bound from a field, so neither backend resolves it to an enum type.
bound_local := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  x := h.t
  match x { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

main := fn() -> u64 {
  if bound_local(Tag.Green) != 22 { return 51 }
  if bound_local(Tag.Red) != 11 { return 52 }
  42
}
