## e2e / issue #1212 — a direct `match` on `alloc::vec::get(S, …)` over a three-word struct.
##
## The direct call scrutinee is staged at the width of the unsubstituted `Option(T)`, which would
## truncate `S` to its first word, so the build refuses it and advises the bound form (which
## test/issue1212_option_deref_struct.al holds correct). The refusal used to name `.map(f)`,
## `.and_then(f)` and `.map_err(g)`, none of which this program contains.
S := struct { a : u64, b : u64, c : u64 }
main := fn() -> u64 {
  match std::os::arena(65536) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      mut v := alloc::vec::with_capacity(S, ptr(mut ar), 4)
      r := alloc::vec::push(S, v, S(a = 1, b = 2, c = 3))
      match alloc::vec::get(S, ptr(v), 0) {
        Some(s) => { s.c }
        None => { 0 }
      }
    }
    Err(_) => { 1 }
  }
}
