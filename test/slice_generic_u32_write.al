## Issue #213 / Types §6.4 / Functions §2.3 / ABI §3.2 / Architecture §7 — a same-module generic
## Slice(u32) parameter must preserve the scalar slice pair and write the selected element without
## changing its neighbours. The read-after-write check observes the value through the same generic
## parameter path; the separate e2e control covers the checked out-of-bounds trap.
## Failure-first evidence: on clean origin/main c9c17b5, the Stage1 compiler emitted and linked this
## fixture but qemu-riscv64 exited 133 through the unsupported IndexAssign fail-loud path.
setw := fn(T : type, s : Slice(T), i : usize, x : T) { s[i] = x }
readw := fn(T : type, s : Slice(T), i : usize) -> T { v := s[i]  v }

main := fn() -> u64 {
  mut arr : [u32; 4] = [10, 20, 30, 40]
  s := arr[0..4]
  setw(u32, s, 1, 99)
  if arr[0] != 10 { return 1 }
  if arr[1] != 99 { return 2 }
  if arr[2] != 30 { return 3 }
  if arr[3] != 40 { return 4 }
  if readw(u32, s, 1) != 99 { return 5 }
  return 42
}
