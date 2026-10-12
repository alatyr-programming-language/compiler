## e2e — docs/ir-slice-1.md §8.5, Types §4.2/§4.3 + Comptime §9.3: a generic body that mixes its
## type parameter with a concrete integer is refused AT THE INSTANTIATION. The generic pass cannot see
## it — `a : T` is `VcUnknown` there and §3.8 forbids defaulting it — so this is the per-instance
## verdict prerequisite (e) exists to deliver: with `T = i64` the body's `a + n` is an `i64` against
## a `usize`, one operator over opposite signedness, ill-formed on every backend and located at the
## body's own `+` (E-Q3). The same body with `T = u64` is accepted (§8.5's other half).
f := fn(T : type, a : T, n : usize) -> T { a + n }
main := fn() -> u64 { return u64(f(i64, 0 - 1, 3)) }
