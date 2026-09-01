## Types §4.4 / §8: these two packed records occupy different byte images even though
## the current word reservation rounds both to one machine word. The conversion must be
## refused before an output artifact is produced.
ByteRecord := @packed struct { value : u8 }
WordRecord := @packed struct { value : u16 }

main := fn() -> u64 {
  source := ByteRecord(value = 42)
  target := unchecked bitcast(WordRecord, source)
  u64(target.value)
}
