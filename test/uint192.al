## e2e — TYP-10 slice A: COMPTIME VALUE parameters + computed array lengths in type-functions
## (Comptime §10 `comptime param`, §1 "parameters (e.g. `comptime N : usize`, an array length)").
## `uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }` is a generic
## type-function whose comptime VALUE parameter `N` (not a `: type` parameter) computes the array
## field's length at instantiation: `uint(192)` is a nominal struct of `192/64 = 3` words (24
## bytes, word 0 = the least-significant word). Before this slice the parser admitted only an
## INT-LITERAL array length in a struct member and rejected a literal instantiation argument
## (`uint(192)` hit the "no const generics" guard in `is_generic_inst`), so this program failed
## to compile. Two different instantiations — `uint(128)` (2 words) and `uint(192)` (3 words) —
## are distinct types coexisting in one program. Result: x.words[0] + x.words[1] = 40 + 2 = 42.
uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }
main := fn() -> u64 {
  mut x : uint(192) = uint(192)(words = [0, 0, 0])
  mut y : uint(128) = uint(128)(words = [0, 0])   ## a DISTINCT instantiation (2 words) coexists
  x.words[0] = 40
  x.words[1] = 2
  y.words[0] = 7
  y.words[0] = y.words[0] - 7                     ## net 0 — keeps the sum at 42
  x.words[0] + x.words[1] + y.words[0] + y.words[1]
}
