## selfhost::scalar_width — the canonical byte width of a named sub-word scalar.
##
## The parser, formatter, and lower_layout all need the same language-level classification when they
## inspect a type-name span. Return the machine width for the known 1/2/4-byte scalar names and 0 for
## word-sized, aggregate, or unknown names. lower_layout owns the separate 8-byte fallback because
## its public query is also used for unresolved names and machine-word operands.

pub subword_bytes := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  if n == 0 { return 0 }
  t := str_at((src + s), n)
  if t == "u8" or t == "i8" or t == "bits8" or t == "bool" { return 1 }
  if t == "u16" or t == "i16" or t == "bits16" { return 2 }
  if t == "u32" or t == "i32" or t == "bits32" or t == "char" or t == "f32" { return 4 }
  0
}
