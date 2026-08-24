## `priv_fn` is NOT `pub`, so §3 makes it nameable by `geo` and by modules nested within `geo` only.
priv_fn := fn() -> u64 { 42 }
pub keep := fn() -> u64 { priv_fn() }
