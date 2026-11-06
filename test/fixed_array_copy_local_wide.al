## e2e — #937, the AGGREGATE- and BYTE-element halves of the same rule: copying a fixed array moves
## its WHOLE block, not one word of it. `rt : [R; 2] = rs` moves four words (two per element) and
## `bt : [u8; 5] = bs` moves the packed byte block, whose data origin is NOT the base slot a word
## array uses. Both were SILENT on x86_64 (`rt[1].a` answered `rs[0].b`, `bt[4]` read past the copy).
## Spec: Types §6.4 + Memory §5.9, as in `fixed_array_copy_local.al`.
## x86_64 ONLY today: on aarch64/riscv64 a by-value aggregate copy is still a fail-loud stub and
## traps (`run/133`), and wasm answers `run/3` — MEASURED unchanged by this fix, i.e. pre-existing and
## tracked by #1191 (aggregate values — literals, by-value copies, aggregate returns — are stubs there).
R := struct { a : u64, b : u64 }

main := fn() -> u64 {
  rs : [R; 2] = [R(a = 1, b = 2), R(a = 3, b = 4)]
  rt : [R; 2] = rs
  if rt[1].a != 3 { return 1 }
  if rt[0].b != 2 { return 2 }
  if rs[1].b != 4 { return 3 }                 ## the source keeps its own block

  bs : [u8; 5] = [1, 2, 3, 4, 5]
  bt : [u8; 5] = bs
  if bt[0] != 1 { return 4 }
  if bt[4] != 5 { return 5 }
  if bs[4] != 5 { return 6 }

  42
}
## expect: run 42
