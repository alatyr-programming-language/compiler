## A user generic over a user generic struct, in a module whose file name mangles like the standard
## library's `alloc::vec`. Each check owns a code from 100 up; 42 means all held.
Box := fn(T : type) -> type { struct { v : T, tag : u64 } }
bget := fn(T : type, b : ptr(Box(T))) -> T { deref(b).v }

E := enum { X, Y(u64) }
val := fn(e : E) -> u64 { match e { E.Y(k) => { k }; E.X => { 1 } } }

pub run := fn() -> u64 {
  be : Box(E) = Box(E)(v = E.Y(7), tag = 1)
  e := be.bget()
  if val(e) != 7 { return 100 }
  35 + val(e)
}
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
