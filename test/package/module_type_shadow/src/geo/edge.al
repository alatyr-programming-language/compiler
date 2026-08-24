## Shadows the ancestor's ENUM with its own, narrower one. 8 + 12 = 20.
E := enum { A, B }                               ## 8 — a payload-less enum is one tag word
pub run := fn() -> u64 { return size(E) + 12 }
