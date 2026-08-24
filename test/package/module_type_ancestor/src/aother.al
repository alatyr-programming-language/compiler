## A DECOY: an unrelated module, non-`pub`, that nothing in `geo`s subtree may name (§3). Every
## shape is deliberately WIDER than `geo`s, so resolving here is a wrong VALUE rather than a trap —
## a silent wrong value is exactly the outcome this fixture forbids.
Box := struct { a : u64, b : u64, c : u64, d : u64 }
U := union { n(u64), big(u64, u64, u64, u64) }
E := enum { Hit(u64), Miss, Big(u64, u64, u64) }
Handle := Box
never_ok_a := fn(v : u64) -> bool { return v == 0 }
Nz := @require(never_ok_a) u64
