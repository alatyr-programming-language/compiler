## The production library drops this entry module. Its stdlib call must not become a library root.
main := fn() -> u64 {
  std::io::print("")
  0
}
