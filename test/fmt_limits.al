## §5 fmt: a leading `##` comment now attaches to an `@limits(...)` decl (fmt_decl_anchor anchors at
## the `@`, since name_start points inside `@limits(`). Comment fidelity + the directive round-trip.
@limits(no_alloc, no_comptime)
main := fn() -> u64 { return 42 }
