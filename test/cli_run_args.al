## P0 CLI boundary regression: `alatyr run <source> -- <arg>` must pass the argument to the
## compiled program, while the compiler must keep it out of the source-path list. The stdlib's
## allocator-backed `std::os::args` is the spec-defined process-input surface (Stdlib §7 / STD-3).
main := fn() -> u64 {
  own := std::os::arena(131072)
  mut ar := std::os::region(ptr(own))
  av := std::os::args(ptr(mut ar))
  mut ok : u64 = 0
  ## argv[0] is the temporary executable and the CLI passes exactly one value after `--`.
  if av.len == 2 { ok = 42 }
  std::os::free(own)
  return ok
}
