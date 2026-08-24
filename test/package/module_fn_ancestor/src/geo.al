## `geo`'s OWN items. Neither is `pub`: §3 down-tree privacy is exactly what makes them reachable from
## `geo::child` and `geo::deep::leaf` without exposing them upward.
helper := fn() -> u64 { return 20 }
gid := fn(T : type, x : T) -> T { return x + 5 }
