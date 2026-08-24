## Use-after-free (spec §10 / D86): a call whose name ends `_free` DISCHARGES its handle argument, so
## a later mention of the handle is a use-after-consume error — check must reject (rc 1). `my_free` is a
## local stand-in for the stdlib frees (strbuf_free/hashmap_free/…), which are consumers by convention.
my_free := fn(s : u64) -> u64 { 0 }
main := fn() -> u64 {
  x := 5
  r := my_free(x)
  y := x
  y
}
