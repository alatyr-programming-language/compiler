## A DESCENDANT reaching its ancestor's non-`pub` helper by the BARE name — the exact spelling this
## issue tightens, and the one Modules §3 lines 80-85 explicitly permit ("a descendant module sees
## its ancestors' non-`pub` items; this is what lets a submodule use its parent's internal helpers").
pub from_ancestor := fn() -> u64 { return helper() + 4 }
