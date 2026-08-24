## §5 fmt: `pub` VISIBILITY round-trips (was dropped — the parser consumes the keyword and it is not
## stored on the Decl, so fmt recovers it by source-scan before name_start). A pub value, a pub fn,
## and a pub struct all keep their `pub `. dbl(20)+2 = 42.
pub STEP := 2
pub Pt := struct { x : u64, y : u64 }
pub dbl := fn(v : u64) -> u64 { v + v }
main := fn() -> u64 { dbl(20) + STEP }
