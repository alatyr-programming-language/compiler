## A `{}`-template variadic `print` whose TEMPLATE is not a string literal. Functions §7.1 specifies
## the expansion over the template's LITERAL text, so there is nothing to expand — and the lower
## used to answer that by emitting NOTHING for the whole statement, deleting the call and its side
## effect with no diagnostic. It must fail LOUD instead (I11); `check` does not model the desugar,
## so this is a BUILD reject.
main := fn() -> u64 {
  t : str = "hi\n"
  print(t)
  return 7
}
