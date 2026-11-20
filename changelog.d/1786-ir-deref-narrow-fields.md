- The shared IR builds a read or write through a pointer to a struct whose fields are scalars narrower
  than a word, laid out one word per field (`deref(p).f`, `p.f`, `p.f = v`, `v : S = deref(p)`). A
  narrow field is read with its width's extension and written as the whole canonical word, so the
  legacy emitters' whole-word accesses still agree (#1786). `alatyr ir` splits the old `expr Deref:
  struct pointee not in the WORD tier` into the cause that refused: a `@packed` or byte-layout struct
  pointee (x86_64's legacy `p.f = v` disagrees on that layout, #1790), a struct pointee with an array
  or aggregate field, or a struct not laid out one word per field.
