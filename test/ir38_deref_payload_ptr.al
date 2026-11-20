## e2e — IR-38 (#1786 cause 4): `deref(q)` read WHOLE where `q` is a match payload binding, which has no
## declaration of its own. Its type is the generic enum instance's payload with the instance's argument
## substituted (`Option(ptr(S))` binds `T` to `ptr(S)`, so `q : ptr(S)`): sema records that for the
## `deref` node (docs/ir.md §3.8 item 8), and the builder lays the pointee out from it.
##   * `Option(ptr(S))` — the library's generic enum, a niche-folded one-word instance;
##   * `Ref(S)` — a generic enum of this program whose payload spells `ptr(T)`.
## The enum pointee is in `test/ir38_deref_recorded_enum.al`. Each check answers its own code when it
## fails; 42 when all held.
S := struct { a : u64, b : u64 }
Ref := fn(T : type) -> type { return enum { Nil, At(ptr(T)) } }

opt_sum := fn(o : Option(ptr(S))) -> u64 {
  match o {
    Some(q) => {
      v := deref(q)
      return v.a * 10 + v.b
    }
    None => { return 7 }
  }
}
ref_sum := fn(r : Ref(S)) -> u64 {
  match r {
    At(q) => {
      v := deref(q)
      return v.a + v.b
    }
    Nil => { return 5 }
  }
}
some_s := fn(q : ptr(S)) -> Option(ptr(S)) { Option(ptr(S)).Some(q) }
at_s := fn(q : ptr(S)) -> Ref(S) { Ref(S).At(q) }

main := fn() -> u64 {
  mut s := S(a = 3, b = 4)
  if opt_sum(some_s(ptr(s))) != 34 { return 1 }
  if opt_sum(Option(ptr(S)).None) != 7 { return 2 }
  mut t := S(a = 30, b = 12)
  if ref_sum(at_s(ptr(t))) != 42 { return 3 }
  if ref_sum(Ref(S).Nil) != 5 { return 4 }
  42
}
## expect: run 42
