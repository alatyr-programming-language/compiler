## e2e (build_reject_has) — the lower's unsupported comptime-if fold is a Codegen diagnostic.
## The comptime local is accepted by semantic checking but cannot be recovered by the lower.


main := fn() -> u64 {
  mut x : u64 = 5
  comptime v : u64 = 5
  comptime if v == 5 { x = 30 } else { x = 70 }
  return x
}
