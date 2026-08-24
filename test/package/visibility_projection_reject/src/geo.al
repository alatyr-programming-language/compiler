priv_fn := fn() -> u64 { 42 }
pub keep := fn() -> u64 { priv_fn() }
