## ROADMAP §4: MUTATING a str field of a mutable-GLOBAL struct (`STATE.name = "…"`). Like the enum
## case, the global field-write path stored a single word, dropping the str's `len` (and clobbering
## the following field). Now a str field materializes {ptr, len} via emit_str_assign and copies both
## words to .data ASCENDING. name "hi" → "worldww"; len(7) + n(5) = 12.
S := struct { name : str, n : u64 }
mut STATE := S(name = "hi", n = 5)
main := fn() -> u64 {
  STATE.name = "worldww"
  return STATE.name.len + STATE.n
}
