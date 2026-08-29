## e2e — a GENERIC index WRITE `s[i] = x` on a `Slice(T)` PARAM (T a type-param). The generic param's
## element `T` was not substituted at bind time, so `Slice(T)` matched no scalar/struct/enum and the
## param mis-bound as a LOCAL array (is_ref=false) — `s[i]` then used the slot ADDRESS instead of the
## by-ref block pointer, so the WRITE overwrote the param slot (lost) and a READ returned the block ptr.
## Now the element is substituted (Slice(T) -> Slice(u64)) so it binds by-ref. Returns 42 iff exact.
## Failure-first evidence (parent f98c62f): the seed-built compiler emitted `ebreak` for `setw__u64`;
## assembly and link succeeded, then qemu-riscv64 exited 133. The fixed tree follows the same path to
## exit 42; x86_64 and AArch64 controls remain 42.
setw := fn(T : type, s : Slice(T), i : usize, x : T) { s[i] = x }
readw := fn(T : type, s : Slice(T), i : usize) -> T { v := s[i]  v }

main := fn() -> u64 {
  arr : [u64; 4] = [10, 20, 30, 40]
  s := arr[0..4]
  setw(u64, s, 1, 99)                 ## arr[1] = 99
  if arr[1] != 99 { return 1 }
  if readw(u64, s, 2) != 30 { return 2 }   ## generic read still correct
  setw(u64, s, 3, 7)
  if arr[3] != 7 { return 3 }
  return 42
}
