## Modules §4.3 — "A re-export may name only `pub` items. A descendant's down-tree access to an
## ancestor's non-`pub` item (§4.1) is for LOCAL use only; re-exporting it is a compile error —
## otherwise a submodule could re-publish an ancestor's private helper upward, overriding the owner's
## deliberate privacy." The BARE read on the next line would be legal; the `pub` binding is not.
pub leaked := geo::priv_fn
pub local_use := fn() -> u64 { geo::priv_fn() }
