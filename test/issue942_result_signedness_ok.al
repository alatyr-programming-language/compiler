## e2e — #942, the accepted half of the result-sink rule (Types §4.2/§4.3, §2.3, §9.1). An explicit
## `u64(v)`, a literal (which takes the declared result's type), a same-signedness widen and a local
## declared with the type it is returned as all stay accepted.
conv := fn(x : i64) -> u64 { u64(x) }
lit := fn() -> u64 { return 30 }
widen := fn(x : u8) -> u64 { x }
spelled := fn() -> u64 {
  mut acc : u64 = 0
  acc = acc + 2
  return acc
}
neg := fn(x : i32) -> i64 {
  if x < 0 { return x }
  0
}
main := fn() -> u64 {
  w : u8 = 6
  r := conv(4) + lit() + widen(w) + spelled()
  if neg(0 - 5) != 0 - 5 { return 1 }
  r
}
