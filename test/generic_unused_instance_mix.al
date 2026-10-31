## e2e — docs/ir-slice-1.md §8.5 + Comptime §9.3: a generic body that WOULD mix its type parameter
## with a concrete integer is ACCEPTED while it is never instantiated — there is no abstract check, so
## nothing decides `T` and the body's `a + n` stays `VcUnknown` (§3.8: a gap to close, never a
## default). The declaration alone must not refuse the program; only an instantiation does. 42.
h := fn(T : type, a : T, n : usize) -> T { a + n }
main := fn() -> u64 { return 42 }
## expect: run 42
