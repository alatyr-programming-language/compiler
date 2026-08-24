## The dependency module is qualified by its package-local alias and its
## complete source path.
main := fn() -> u64 {
  return d::lib::thing::answer()
}
