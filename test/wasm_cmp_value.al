## A comparison result used as a VALUE. Types §4.2/§4.3 make `bool` -> integer the numeric class, which is
## always explicit, so the value is written `u64(10 > 3)`; the bare `(10 > 3) + 41` this fixture held was
## accepted only while `check_expr`'s `Bin` arm never ran (#716).
main := fn() -> u64 { return u64(10 > 3) + 41 }
