S := struct { a : u64, b : u64 }
mk := fn() -> S { S(a = 3, b = 4) }
pick := fn(x : u64) -> u64 { x }
main := fn() -> u64 { pick(mk()) + 38 }
## Compiled alone (the corpus walk), this file is the same ill-formed call with no `zed` beside it.
## expect: reject
