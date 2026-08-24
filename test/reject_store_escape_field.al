## Store-escape into a FIELD of a module mut global aggregate (spec Memory §5.3.1: "a field of any
## aggregate that outlives R"). `G` is a mut global `Box` whose `p` field is a pointer; `G.p = ptr(x)`
## stores a dying stack address into a static place → forbidden upward flow. Check must reject (rc 1).
Box := struct { p : ptr(u64) }
SENTINEL := 0
mut G := Box(p = ptr(SENTINEL))
leak := fn() {
  x := 5
  G.p = ptr(x)
}
main := fn() -> u64 { 0 }
