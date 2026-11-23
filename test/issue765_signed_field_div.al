## e2e / issue #765 — `/` and `%` with an `i64` struct FIELD as an operand divide SIGNED.
##
## The operands' types decide a division's signedness (Types §3.2). aarch64, riscv64 and wasm found no
## signedness for a field operand and divided unsigned; x86_64 did the same for the field of a CALL
## result (`mk().k / 9`). Covered: the field as dividend (`/`, `%`) of a local and of a by-value
## parameter, as divisor (`unchecked (… % s.k)`, `… / s.k`), and the field of a call result. Each check
## owns a code from 11 up; 42 means every quotient and remainder was signed.
##
## NON-VACUOUS: at `b8cf45d` the local-field rows answered 1 on aarch64, riscv64 and wasm (x86_64 42);
## at `3e5d7b4` (progen run 36740214181) `mk().k / 9` and `mk().k % 9` answered 1 on x86_64 and trapped
## on the twins. At `dc9e18e2` every row answers 42 on all four backends.
S := struct { k : i64 }

g := fn(s : S) -> i64 { return s.k / 9 }

mk := fn() -> S { return S(k = 0 - 42) }

main := fn() -> u64 {
  s := S(k = 0 - 100)
  q : i64 = s.k / 9
  if q != 0 - 11 { return 11 }
  r : i64 = s.k % 9
  if r != 0 - 1 { return 12 }
  if g(S(k = 0 - 100)) != 0 - 11 { return 13 }
  d := S(k = 3)
  m : i64 = unchecked ((0 - 7) % d.k)
  if m != 0 - 1 { return 14 }
  e : i64 = (0 - 7) / d.k
  if e != 0 - 2 { return 15 }
  c : i64 = mk().k / 9
  if c != 0 - 4 { return 16 }
  c2 : i64 = mk().k % 9
  if c2 != 0 - 6 { return 17 }
  42
}
## expect: run 42
