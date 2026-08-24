## build_reject_has — a `Slice(str)` element is a two-word `{ptr,len}` value, not a scalar word.
## The lower accepts it in str contexts and whole-value bindings; an unsupported scalar call edge must
## stop at the located lower guard instead of silently passing only the element's pointer.
take_u64 := fn(x : u64) -> u64 { x }

bad := fn(s : Slice(str)) -> u64 {
  take_u64(s[0])
}

main := fn() -> u64 {
  bad(Slice(str)(ptr = unchecked bitcast(ptr(str), 0), len = 0))
}
