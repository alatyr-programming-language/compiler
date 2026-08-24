## `priv_fn` is NOT `pub`. Its DESCENDANT `geo::child` may NAME it (§3, down-tree privacy) but may
## not re-publish it upward (§4.3).
priv_fn := fn() -> u64 { 42 }
pub keep := fn() -> u64 { priv_fn() }
