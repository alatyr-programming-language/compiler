## Shadows the ancestor's STRUCT with its own, narrower one. 8 + 14 = 22.
Box := struct { a : u64 }                        ## 8 — must win over `geo`s 16
pub run := fn() -> u64 { return Box.size() + 14 }
