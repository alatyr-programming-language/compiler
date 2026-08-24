## `lower_attrs::decl_is_pub` used to require `pub` IMMEDIATELY before the name, so `pub mut NAME` —
## the ONLY spelling a mutable global has (Declarations §2 puts `pub` before the whole declaration,
## `mut` included) — read as NON-`pub`. That predicate gates a library's symbol visibility
## (`mangled_symbol_is_global`) and the `iface.al` public-surface hash, so a `pub mut` global was
## emitted as a LOCAL symbol (`d api__COUNT`) and was MISSING from the interface summary: a library
## consumer could not link it and no interface hash recorded it. Measured before the fix:
##   `d api__COUNT` / `decl_count` short by one. After: `D api__COUNT`, present in the summary.
pub mut COUNT : u64 = 7
mut PRIVATE_COUNT : u64 = 1
pub bump := fn() -> u64 { COUNT = COUNT + PRIVATE_COUNT ; COUNT }
