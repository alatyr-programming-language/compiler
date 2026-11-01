Q := struct { y : u64 }
cfg : u64 = 3
lim : Q = Q(y = 4)
pub other := fn() -> u64 { cfg + lim.y }
