## IR slice 4a (`docs/ir-slice-4.md`): a `match` over an integer scrutinee, built from the shared IR on
## every twin — literal arms and `_` in statement position, range arms `lo..=hi` (#821: every range
## match trapped on aarch64, riscv64 and wasm), and a value `match`. The arms are tested top to bottom,
## so `classify(7)` takes `_`. 6 + 30 + 2 * 3 = 42.
classify := fn(x : u64) -> u64 {
  match x {
    0 => { return 1 }
    1 => { return 2 }
    _ => { return 3 }
  }
}
main := fn() -> u64 {
  s := classify(0) + classify(1) + classify(7)
  n : u8 = 200
  r : u64 = match n { 0..=127 => 1 ; 128..=255 => 2 }
  v : u64 = match s { 6 => 30 ; _ => 0 }
  v + s + r * 3
}
