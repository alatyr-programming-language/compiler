## e2e (#1268) — a field's declared type is the context of the value stored into it (Declarations §3.4:
## the target place), directly and through a pointer local (`p.f = 7 - 9`, `p : ptr(mut S)`, the
## compiler's own `cx.call_cidx = 0 - 1` shape). Never an unsigned subtraction that borrows.
##
## Expected: 42 on x86_64, aarch64, riscv64 and wasm.
## Measured on the parent (main `c4e20937`, the committed seed 0.2.19 = its Stage1; native x86_64):
## 132 / 42 / 42 / 42 (x86_64's unsigned borrow guard traps).

S := struct { f : i64, g : u64 }

setf := fn(p : ptr(mut S)) { p.f = 7 - 9 }

main := fn() -> i64 {
  mut s := S(f = 3, g = 4)
  s.f = 5 - 6
  if s.f != 0 - 1 { return 1 }
  s.f = 0 - 1
  if s.f != 0 - 1 { return 2 }
  setf(ptr(s))
  if s.f != 0 - 2 { return 3 }
  42
}
## expect: run 42
