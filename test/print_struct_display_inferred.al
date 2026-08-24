## e2e — a `{}`-template `print` hole filled by an INFERRED struct var (`p := Pt(…)`, no annotation)
## renders via structural Display. block_decl_type resolves the inferred type from the RHS StructLit's
## name (the same span the emit reads), so the collected print_one__Pt instance matches the call site.
## Prints "point { x = 40, y = 2 }" (verified manually) and returns 42.
Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  p := Pt(x = 40, y = 2)
  std::fmt::print("point {}\n", p)
  42
}
