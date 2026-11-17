## `T`, `Box` and `E` are declared only here. `Inner` and `Word` are declared here and in `main`.
Inner := struct { a : u64, b : u64 }
T := Inner
Word := u64
Box := struct { k : u64, w : Word }
E := enum { Nil, P(u64, Word) }
pub mk := fn() -> T { Inner(a = 20, b = 22) }
pub sum := fn(t : T) -> u64 { t.a + t.b }
pub mkbox := fn() -> Box { Box(k = 3, w = 4) }
pub unbox := fn(x : Box) -> u64 { x.k + x.w }
pub mke := fn() -> E { E.P(4, 5) }
pub une := fn(e : E) -> u64 {
  match e {
    Nil => { 0 }
    P(n, w) => { n + w }
  }
}
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
