## e2e — multi-word ENUM element WRITE to a LOCAL enum-element array (`arr[i] = Option(i64).Some(v)`),
## both a LITERAL and a VAR RHS. The single-word fallback dropped the payload (disc/word-0 only). Lower
## now copies all `estride` (disc + payload) words to the element base.
main := fn() -> u64 {
  mut arr : [Option(i64); 4] = [Option(i64).None, Option(i64).None, Option(i64).None, Option(i64).None]
  arr[1] = Option(i64).Some(30)         ## literal RHS
  o := Option(i64).Some(12)
  arr[2] = o                             ## var RHS
  mut s := 0
  match arr[1] { Option::Some(v) => { s = s + v } Option::None => { s = s + 0 } }
  match arr[2] { Option::Some(v) => { s = s + v } Option::None => { s = s + 0 } }
  u64(s)                                 ## 30 + 12 = 42
}
