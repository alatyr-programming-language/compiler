## DEFER (Control Flow §9.3 / Memory §5.8): defers run on NORMAL fall-through exit, in LIFO order (last
## registered runs first). `body` registers bump(1), bump(2), bump(3); on exit they run 3, 2, 1. Each
## bump does `ACC = ACC*4 + n`, so LIFO(3,2,1) => 3 -> 14 -> 57 (FIFO would give 1 -> 6 -> 27). main
## reads the global AFTER body returns, so the exit code 57 PROVES both that defers ran and their LIFO order.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 4 + n ; 0 }
body := fn() -> u64 {
  defer bump(1)
  defer bump(2)
  defer bump(3)
  0
}
main := fn() -> u64 {
  x := body()
  return ACC
}
