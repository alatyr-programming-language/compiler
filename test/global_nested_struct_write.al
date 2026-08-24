## WRITING a whole NESTED struct field of a mutable-global struct (`STATE.inner = P(…)`),
## then reading its scalar fields back. The write materializes the struct into the match scratch and
## copies its words to .data ascending; the read is the 2-level nested-field read. 10+27+5 = 42.
P := struct { a : u64, b : u64 }
Outer := struct { inner : P, n : u64 }
mut STATE := Outer(inner = P(a = 1, b = 2), n = 5)
main := fn() -> u64 {
  STATE.inner = P(a = 10, b = 27)
  return STATE.inner.a + STATE.inner.b + STATE.n
}
