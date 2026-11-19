## `b`'s own `twice` is the one its bare call means; `step` here is a decoy for `main`'s import of `a`'s.
twice := fn(x : u64) -> u64 { x * 3 }
pub step := fn(x : u64) -> u64 { x + 100 }
pub half := fn(x : u64) -> u64 { x / 2 }
pub dec := fn(x : u64) -> u64 { x - 1 }
pub useb := fn(x : u64) -> u64 { twice(x) + 1 }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
