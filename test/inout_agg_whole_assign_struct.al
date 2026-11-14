## e2e — #1633: a whole-value assignment `p = v` to an `in out` STRUCT parameter must reach the caller's
## place (Functions §2.1, §2.3, §4.1), so `setp(v)` leaves `v` the `P(30, 12)` it wrote: 42.
## No backend lowers the whole store yet: the shared IR declines `setp` (`stmt Assign`), and the legacy
## emitters never wrote it back. MEASURED at #1631's parent c28efe91 and at its first head 6a44bc34
## (native x86_64): x86_64 refused, and aarch64, riscv64 and wasm answered 2, the caller's old value.
## Now every backend refuses the build, located at the assignment; the four rows in
## scripts/known-deviations.tsv name #1633 and are deleted when the IR builds the store.
## expect: run 42
P := struct { x : u64, y : u64 }

setp := fn(in out p : P) { p = P(x = 30, y = 12) }

main := fn() -> u64 {
  mut v := P(x = 1, y = 1)
  setp(v)
  v.x + v.y
}
