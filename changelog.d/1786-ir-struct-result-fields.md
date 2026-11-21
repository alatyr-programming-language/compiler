- The shared IR builds functions that return, or call a function returning, a struct whose fields are
  sub-word scalars, `bool`, fixed arrays of word scalars, word-stored nested structs or scalar-only
  enums (#1786). A narrow field is returned as its canonical whole word, as the legacy emitters read
  it; on x86_64 a struct result of up to seven words travels in the legacy register set. A struct
  field that is not stored word by word, or an enum field that is generic, folded or holds an
  aggregate, is refused at build with its own located label.
