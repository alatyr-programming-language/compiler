## `helper` is declared HERE as well, so the nearest declaration — this one — must win over `geo`s
## and over the decoys. `bump` is not, so it resolves one step up, to `geo`'s and not to the decoys.
helper := fn() -> u64 { return 30 }
pub run := fn() -> u64 { return helper() + bump() }
