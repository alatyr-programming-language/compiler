P := struct { x : u64 }
cfg : P = P(x = 5)
pub other := fn() -> u64 { cfg.x }
