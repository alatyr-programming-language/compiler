## e2e / issue #1212 — `alloc::vec::get` over a seven-word struct.
##
## The payload of the enum built from the pointee is wider than the six payload registers, so the
## build refuses it rather than truncating. The refusal is located: it prints the source line of
## the enum constructor it reached inside the container, then the reason. Before, the reason came
## alone and nothing showed where.
S7 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64 }
main := fn() -> u64 {
  match std::os::arena(65536) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      mut v := alloc::vec::with_capacity(S7, ptr(mut ar), 4)
      r := alloc::vec::push(S7, v, S7(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 42))
      o := alloc::vec::get(S7, ptr(v), 0)
      match o {
        Some(s) => { s.g }
        None => { 0 }
      }
    }
    Err(_) => { 1 }
  }
}
