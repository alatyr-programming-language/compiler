## Dangling pointer (spec Memory §5): returning ptr(x) where x is a fn-scoped local escapes the address
## of a stack slot that dies at the return — ill-formed, check must reject (rc 1).
f := fn() -> ptr(u64) {
  x := 5
  return ptr(x)
}
main := fn() -> u64 { 0 }
