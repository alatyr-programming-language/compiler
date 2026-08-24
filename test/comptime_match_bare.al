## e2e — a COMPTIME-MATCH arm whose body is a BARE nested `comptime match` (no `{}` block). The
## parser must parse it as a single statement, not consume a phantom `{` and drift (which corrupted
## the enclosing decl — e.g. alloc::fmt::display losing its generic-ness). u64 → Scalar arm → the
## nested bare `comptime match k` → its `_` arm → 42.
knd := fn(T : type, v : T) -> u64 {
  comptime match typeinfo(T) {
    Struct(_) => { return 1 }
    Scalar(b, k) => comptime match k {
      _ => { return 42 }
    }
    _ => { return 9 }
  }
}
main := fn() -> u64 { return knd(u64, 5) }
