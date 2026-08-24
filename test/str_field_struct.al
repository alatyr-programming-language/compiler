## e2e (§4 layout — a `str` FIELD inside a struct). A `str` is a 2-word `{ptr, len}` value (Memory
## §3.5), so a `str` field occupies TWO words and shifts every later field's offset. Exercises BOTH
## a struct LOCAL and a MUTABLE-GLOBAL struct, each with a `str` field FOLLOWED by a scalar field (so
## the scalar's word offset must account for the 2-word str): construction stores `{ptr, len}` (like a
## str local), `g.name.len` reads the str's second word, and `g.n` reads the shifted scalar cell. The
## global additionally lays the `str` field out in `.data` as `{.Lstr<idx>, len}`. `src/` uses spans
## (`s`/`n : usize`), not `str` fields, so this stays fixpoint-neutral.
G := struct { name : str, n : u64 }
mut gg := G(name = "hello", n = 7)     ## mutable-global struct with a leading str field

by_local := fn() -> u64 {
  mut g := G(name = "hi", n = 30)
  ## str-field WRITE: reassign the str field (a 2-word {ptr,len} store), then read the new len
  g.name = "abc"                       ## name.len now 3
  ## g.name.len = 3, g.n = 30 (n is at word 2, after the 2-word str)
  g.name.len + g.n - 1                 ## 3 + 30 - 1 = 32
}

## a struct with a str field passed BY REFERENCE — `s.name.len` reads through the caller's pointer at
## the str field's down-growing pointee offset.
by_ref := fn(s : G) -> u64 { s.name.len + s.n }

## a factory RETURNING a struct with a str field — the str field's {ptr, len} ride the struct-return
## register convention (word 0 ptr, word 1 len, word 2 n), delivered as two words not one.
mk := fn() -> G { G(name = "hey", n = 0) }

main := fn() -> u64 {
  a := by_local()                      ## 32
  ## global: gg.name.len = 5 ("hello"), gg.n = 7 (word 2)
  b := gg.name.len + gg.n - 2          ## 5 + 7 - 2 = 10
  p := G(name = "ok", n = 0)
  c := by_ref(p) - 2                   ## (2 + 0) - 2 = 0
  r := mk()                            ## returned struct with a str field
  d := r.name.len - 3                  ## "hey".len = 3 → 0
  a + b + c + d                        ## 32 + 10 + 0 + 0 = 42
}
