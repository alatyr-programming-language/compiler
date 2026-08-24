Priv := struct { v : u64 }
pub keep := fn() -> u64 { p := Priv(v = 42) ; p.v }
