## e2e — a `{}`-template `print` hole filled by a TYPED struct var renders via structural Display
## (`print_one__Pt`). Previously the call-site type tag mangled the local's `Pt(x = 40, …)` initializer
## as if `(x = 40, y = 2)` were generic type-arguments → an invalid symbol `Pt_x = 40_y = 2` that never
## matched the `print_one__Pt` definition. Now the struct-literal parens are not scanned as type-args.
## Prints "point { x = 40, y = 2 }" (verified manually) and returns 42.
Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  p : Pt = Pt(x = 40, y = 2)
  std::fmt::print("point {}\n", p)
  42
}
