## IR #1705: an index of a fixed array of STRUCT elements is checked like a scalar array's (Types §6.4;
## I11): `pick(2)` on a `[P; 2]` traps before any element is read; the in-range call before it answers.
P := struct { a : u64, b : u64 }
pick := fn(i : usize) -> u64 {
  xs : [P; 2] = [P(a = 40, b = 1), P(a = 41, b = 1)]
  xs[i].a + xs[i].b
}
main := fn() -> u64 {
  ok := pick(1)
  if ok != 42 { return 1 }
  pick(2)
}
## expect: trap
