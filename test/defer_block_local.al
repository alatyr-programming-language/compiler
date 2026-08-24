## DEFER (§9.3): a `defer { … }` BLOCK whose body declares a LOCAL and uses a STRING LITERAL — proves
## the block's statements are still ordinary statements to the slot-collector and `.rodata` walker (a
## local gets a frame slot, the literal a `.rodata` entry). `f` defers { s := "hello"; ACC = uses(s) },
## and `uses` returns the string's byte length (5) — so ACC = 5 proves the block's slot + rodata resolve.
## `main` reads ACC AFTER `f` returned (the return value is eval'ed before the drain).
mut ACC : u64 = 0
uses := fn(s : str) -> u64 { u64(s.len()) }
f := fn() -> u64 {
  defer {
    mut s := "hello"
    ACC = uses(s)
  }
  return ACC
}
main := fn() -> u64 { _ := f() ; return ACC }