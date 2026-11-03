## #1181 — a `[str; N]` literal whose elements are str LOCALS, not str literals, holds each local's
## two-word pair: the declared element type decides the layout (Types §7). Expected exit 23: the
## lengths 2 and 3.
main := fn() -> u64 {
  x : str = "abc"
  y : str = "de"
  t : [str; 2] = [x, y]
  u64(t[1].len) * 10 + u64(t[0].len)
}
## expect: run 23
