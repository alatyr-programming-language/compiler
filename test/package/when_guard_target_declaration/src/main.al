## Issue #251 / TOOL-17: on parent main 2828f9e, check and build reject this valid package with
## `duplicate name at line 2 in main`; the false branches must be absent before name resolution.
pub kind_probe := fn() -> u64 when target.kind == Kind.object { return 20 }
pub kind_probe := fn() -> u64 when target.kind != Kind.object { return missing_kind_branch() }
pub size_probe := fn() -> u64 when target.code_size == CodeSize.b32 { return 22 }
pub size_probe := fn() -> u64 when target.code_size != CodeSize.b32 { return missing_size_branch() }
