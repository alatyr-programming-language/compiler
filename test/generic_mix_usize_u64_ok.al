## e2e — docs/ir-slice-1.md §8.5, the ACCEPT half of `generic_mix_usize_reject`: the same body,
## instantiated with `T = u64`, is well-typed — `a + n` is a `u64` against a `usize`, both unsigned,
## so the per-instance refusal does not fire and the program runs. This is what pins the verdict to
## the instance's OWN signedness rather than to the body's shape: a rule that refused every generic
## `T`-plus-integer body would fail here, and one that never looked at instances would fail the
## reject half. 39 + 3 = 42 on every backend.
g := fn(T : type, a : T, n : usize) -> T { a + n }
main := fn() -> u64 { return u64(g(u64, 39, 3)) }
## expect: run 42
