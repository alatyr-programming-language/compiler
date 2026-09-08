## An ancestor module with a PRIVATE helper. Modules §3 lines 80-85: `geo` may name it, and so may
## every module nested within `geo`. Nothing outside that subtree may.
helper := fn() -> u64 { return 7 }

pub run := fn() -> u64 { return helper() }
