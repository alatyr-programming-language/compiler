## A `_free` discharge as the terminal use of the handle (no later mention) — check ACCEPTS. Guards
## against a false positive in the use-after-free check (the corpus's free sites are all terminal).
my_free := fn(s : u64) -> u64 { 0 }
main := fn() -> u64 {
  x := 5
  r := my_free(x)
  r
}
