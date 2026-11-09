## #1397 — two calls to a generic fn returning `Option(T)` compared directly. By Stdlib appendix §2.6 the
## first comparison is false and the second true. The x86_64 routing types a generic call's result only
## for a `-> T` return, so the build must stop at the comparison's source line rather than compare
## word 0 (where `Some(1)` and `Some(2)` read equal).

wrap := fn(T : type, v : T) -> Option(T) { Option.Some(v) }

main := fn() -> u64 {
  if wrap(u64, 1) == wrap(u64, 2) { return 12 }
  if not (wrap(u64, 1) == wrap(u64, 1)) { return 13 }
  42
}
## expect: reject "result with a multi-word struct/enum value is not yet supported"
