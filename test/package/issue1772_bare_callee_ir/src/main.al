twice := fn(x : u64) -> u64 { x * 4 }
step := a::step
(half, dec) := b
pick := fn(x : u64) -> u64 { x + 1 }
pick := fn(x : u8) -> u64 { u64(x) }
## A literal argument to a bare callee whose name several modules declare is left untyped by sema
## (`sema-gap literal`, #1772), so the arguments here are typed locals.
mine := fn(x : u64) -> u64 { twice(x) }
imported := fn(x : u64, y : u64, z : u64) -> u64 { step(x) + half(y) + dec(z) }
theirs := fn() -> u64 { b::useb(4) }
over := fn() -> u64 { pick(u8(3)) }
main := fn() -> u64 { mine(2) + imported(9, 8, 5) + theirs() + over() }
## Compiled alone (the corpus walk), this file names modules `a` and `b` it does not have.
## expect: reject
