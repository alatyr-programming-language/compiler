## `Priv` is NOT `pub`: a type is a declaration like any other, so §3 governs it identically.
Priv := struct { v : u64 }
pub keep := fn() -> u64 { p := Priv(v = 42) ; p.v }
