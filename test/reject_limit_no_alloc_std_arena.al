## sema/limits (FND-10/FND-11, Memory §5.2): `no_alloc` covers the standard
## arena constructor, not only a user-spelled `allocate` helper.
@limits(no_alloc)
touch_alloc := fn() -> u64 {
  ar := std::os::arena(4096)
  42
}
main := fn() -> u64 { return touch_alloc() }
