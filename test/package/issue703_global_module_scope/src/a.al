P := struct { x : u64 }
cfg : P = P(x = 5)
lim : u64 = 7
pub get := fn() -> u64 { cfg.x + lim }
