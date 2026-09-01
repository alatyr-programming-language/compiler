## Types §4.4 / §8: two distinct packed declarations with the same exact byte image
## remain valid bitcast targets in both checked and unchecked forms.
PackedLeft := @packed struct { first : u8, rest : u16 }
PackedRight := @packed struct { first : u8, rest : u16 }

main := fn() -> u64 {
  source := PackedLeft(first = 10, rest = 300)
  checked := bitcast(PackedRight, source)
  unchecked_value := unchecked bitcast(PackedRight, source)
  if size(PackedLeft) != 3 { return 90 }
  if size(PackedRight) != 3 { return 91 }
  if u64(checked.first) != 10 { return 1 }
  if u64(checked.rest) != 300 { return 2 }
  if u64(unchecked_value.first) != 10 { return 3 }
  if u64(unchecked_value.rest) != 300 { return 4 }
  return 42
}
