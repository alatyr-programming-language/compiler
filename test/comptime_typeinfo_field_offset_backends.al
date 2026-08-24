## CT-6 cross-backend regression: every backend folds Field.offset from the same shared layout
## contract. The result covers ordinary word layout, @packed byte layout, and the standard direct
## byte-array layout. This fixture is intentionally not registered in scripts/e2e.sh; the lane runs
## it directly through each owned emitter so unavailable qemu/wasmtime are reported as skips.
S := struct { x : u64, y : u64, z : u64 }
P := @packed struct { a : u8, b : u32, c : u16 }
B := struct { data : [u8; 4], tail : u16 }

sum_offsets := fn(T : type) -> u64 {
  mut total : u64 = 0
  comptime for f in typeinfo(T).fields { total = total + f.offset }
  total
}

main := fn() -> u64 { sum_offsets(S) + sum_offsets(P) + sum_offsets(B) }
