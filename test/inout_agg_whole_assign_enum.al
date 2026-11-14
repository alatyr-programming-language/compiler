## e2e — #1633: a whole-value assignment `e = v` to an `in out` ENUM parameter must reach the caller's
## place. Functions §2.1: `in out` denotes the caller's place; §2.3: it is bound by a mutable place,
## read and written in place; §4.1: passed by reference to that place. So `setb(s.e)` leaves `s.e` the
## `B(30, 11)` it wrote, and `main` answers 30 + 11 + 1 = 42.
## No backend lowers the whole store yet: the shared IR declines `setb` (`stmt Assign`), and the legacy
## emitters never wrote it back. MEASURED at #1631's parent c28efe91 (native x86_64): x86_64 refused,
## aarch64 trapped 133, riscv64 133, wasm 134; at #1631's first head 6a44bc34 (`main` built by the IR,
## `setb` legacy) the twins answered 2 on all three, the caller's old value. Now every backend refuses
## the build, located at the assignment; the four rows in scripts/known-deviations.tsv name #1633 and
## are deleted when the IR builds the store.
## expect: run 42
E := enum { A(u64), B(u64, u64) }
S := struct { k : u64, e : E }

setb := fn(in out e : E) { e = E.B(30, 11) }

main := fn() -> u64 {
  mut s := S(k = 1, e = E.A(5))
  setb(s.e)
  match s.e {
    E::A(x) => { 2 }
    E::B(x, y) => { x + y + s.k }
  }
}
