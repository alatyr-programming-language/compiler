## §5 fmt: a statement `match` on a `str` scrutinee with STR-LITERAL patterns (`"lit" => { … }`)
## now round-trips (was fail-loud: "str/comptime statement-match arm not modelled"). Both the
## statement-match and value-match arm printers recover the `Expr::StrLit` pattern node from the
## arm's `lit` handle and render it `"…"`. classify("yes") = 1; 1 + 41 = 42.
classify := fn(s : str) -> u64 {
  match s {
    "yes" => { return 1 }
    "no" => { return 0 }
    _ => { return 2 }
  }
}

main := fn() -> u64 {
  return classify("yes") + 41
}
