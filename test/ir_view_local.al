## e2e — #1576 step 1: a slice view LOCAL is built by the shared IR on the register twins and wasm, as
## the two-word pair the spec lays out (Types §7: a `[T]` binding holds pointer + length, 16 bytes;
## Stdlib appendix §3.5: `struct { ptr : ptr(T), len : usize }`). The view is taken by a literal-bound
## range slice of a fixed array local (`xs[1..4]`, in range, so no sub-slice check is owed), copied
## whole (`t := s`), and read by `.len` and by `s[i]` — literal, dynamic, and inside `unchecked` — each
## checked index against the runtime length word (Stdlib appendix §3.5, Types §6.4: `base + i × stride`).
## Measured on the parent (`cdcecb5c`): x86_64 answered 42; the legacy aarch64 and riscv64 emitters
## could not lower the view reads (`brk #0 // unsupported field access`, `// unsupported index`) and
## exited 133, and legacy wasm hit an `unreachable` in `main`, exit 134. This fixture uses word
## elements only; the builder also takes a narrower scalar element (stride = its width; see
## `ir_view_local_oob`), but x86_64's legacy word-spaced `[u16; N]` range slice is #1514, so a narrow
## element here would not agree across backends.
sum_mid := fn() -> u64 {
  xs : [u64; 5] = [1, 2, 3, 4, 5]
  s : Slice(u64) = xs[1..4]
  mut i : usize = 0
  mut acc : u64 = 0
  while i < s.len {
    acc = acc + s[i]
    i = i + 1
  }
  acc
}

main := fn() -> u64 {
  if sum_mid() != 9 { return 1 }
  ys : [i64; 4] = [0 - 7, 20, 0 - 3, 40]
  s : Slice(i64) = ys[0..4]
  t := s
  if t.len != 4 { return 2 }
  if t[0] >= t[2] { return 3 }
  q : i64 = t[0] / 7
  if q != 0 - 1 { return 4 }
  e : [u64; 3] = [6, 7, 8]
  w : Slice(u64) = e[2..2]
  if w.len != 0 { return 5 }
  k : usize = 1
  r : i64 = unchecked s[3]
  if r != 40 { return 6 }
  u64(t[k] + t[3] - 18)
}
## expect: run 42
