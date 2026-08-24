## e2e/fmt — the `[e ; n]` ARRAY-FILL form (Types §6.1). The parser desugars it into n
## copies of ONE element node, so fmt re-emitted it EXPANDED: `[0; 3]` came back `[0, 0, 0]`. Verbose
## but value-preserving there — and a SILENT MISCOMPILE in the other use of the same syntax, an ARRAY
## TYPE passed to a generic fn: `sum_gen([u64; 3], arr)` came back `sum_gen([u64, u64, u64], arr)`,
## which named a different instantiation and mangled to a symbol containing a literal `, ` that the
## assembler rejected outright (`generic_array_param`, `display_array`, `display_array_struct`,
## `comptime_for_typeinfo_n` all died that way after a reformat).
## `zs` is the fill as an initializer (every element is the same node, so it must come back as
## `[0; 3]`); `xs` and `ss` are written-out literals that must NOT be folded into a fill — their
## element nodes are distinct even when the text repeats; `sum_gen([u64; 3], xs)` is the array
## TYPE as a generic type argument, the spelling a reformat used to destroy.
sum_gen := fn(T : type, a : T) -> u64 {
  mut s : u64 = 0
  mut i : usize = 0
  while i < 3 {
    s = s + a[i]
    i = i + 1
  }
  return s
}

main := fn() -> u64 {
  zs : [u64; 3] = [0; 3]
  xs : [u64; 3] = [12, 20, 10]
  ss : [u64; 3] = [7, 7, 7]
  n := sum_gen([u64; 3], xs)
  mut t : u64 = 0
  mut i : usize = 0
  while i < 3 {
    t = t + zs[i] + ss[i]
    i = i + 1
  }
  if t != 21 { return 1 }
  if n != 42 { return 2 }
  return n
}
