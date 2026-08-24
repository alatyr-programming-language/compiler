## `PrivTag` is NOT `pub`.
PrivTag := enum { lo, hi }
pub keep := fn() -> u64 {
  t := PrivTag.hi
  match t {
    PrivTag::lo => { 1 }
    PrivTag::hi => { 42 }
  }
}
