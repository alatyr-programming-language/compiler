## IR slice 5a (`docs/ir-slice-5.md`): brands and required types from the shared IR on every twin. A
## brand or required type in a signature has its underlying scalar's representation, `Id(v)` re-brands,
## `NonZero(v)` runs the `@require` gate (the predicate is called; false would trap `require`), and
## `u64(x)` takes the underlying value back. 20 - 20 + 84 / 2 = 42.
Id := brand(u64)
is_nonzero := fn(v : u64) -> bool { return v != 0 }
NonZero := @require(is_nonzero) u64
twice := fn(x : Id) -> Id { Id(u64(x) * 2) }
inv := fn(n : NonZero) -> u64 { 84 / u64(n) }
main := fn() -> u64 {
  k : Id = Id(10)
  t := twice(k)
  n := NonZero(2)
  u64(t) - 20 + inv(n)
}
