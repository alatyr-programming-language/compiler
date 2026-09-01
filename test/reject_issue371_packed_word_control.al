## Existing unequal-word control: this packed five-byte record and the plain eight-byte
## record already cross different reserved word counts and must remain a located reject.
PackedFive := @packed struct { first : u8, rest : u32 }
PlainWord := struct { value : u64 }

main := fn() -> u64 {
  source := PackedFive(first = 7, rest = 12345)
  target := unchecked bitcast(PlainWord, source)
  target.value
}
