## Use-after-free via the UFCS receiver form (spec §10): `x.my_free()` discharges the receiver x
## (a `_free`-tail method), so the later mention of x is a use-after-consume error — check rejects. This
## is the form the stdlib uses (`sb.strbuf_free()` in lib/std/fmt.al).
my_free := fn(s : u64) -> u64 { 0 }
main := fn() -> u64 {
  x := 5
  r := x.my_free()
  y := x
  y
}
