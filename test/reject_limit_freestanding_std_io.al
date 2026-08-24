## sema/limits (FND-10/FND-11, Overview §3): `freestanding` forbids an OS-facing
## standard-library call even when its syscall is hidden behind `std::io`.
@limits(freestanding)
touch_os := fn() -> u64 {
  std::io::print("")
  42
}
main := fn() -> u64 { return touch_os() }
