## Counting lines, words and bytes over a stream that arrives in chunks.

## The running counts, and whether the last byte seen was inside a word, so a word split across
## two chunks is counted once.
pub Counter := struct {
  lines : u64,
  words : u64,
  bytes : u64,
  in_word : bool,
}

## A counter that has seen nothing.
pub counter := fn() -> Counter {
  Counter(lines = 0, words = 0, bytes = 0, in_word = false)
}

## Whether `b` separates words: space, or one of the controls tab to carriage return.
pub is_space := fn(b : u8) -> bool {
  b == 0x20 or (b >= 0x09 and b <= 0x0D)
}

## Count the bytes of `chunk`. A line is a newline byte; a word is a maximal run of non-space
## bytes.
pub feed := fn(in out k : Counter, chunk : Slice(u8)) {
  for b in chunk {
    k.bytes += 1
    if b == 0x0A { k.lines += 1 }
    if is_space(b) {
      k.in_word = false
    } else if k.in_word == false {
      k.in_word = true
      k.words += 1
    }
  }
}
