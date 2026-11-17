pub S := struct { x : u64, y : u64, a : u64 }
pub mk := fn() -> S { S(x = 1, y = 0, a = 21) }
pub get := fn(p : ptr(mut S)) -> ptr(mut S) { p }
