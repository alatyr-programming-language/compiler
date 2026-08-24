## The DECOY: an unrelated module, non-`pub`, sorting BEFORE `geo.al` in declaration order. Nothing
## in `geo`'s subtree may name any of it (§3), so none of these bodies may ever run.
helper := fn() -> u64 { return 0 }
gid := fn(T : type, x : T) -> T { return x - x }
