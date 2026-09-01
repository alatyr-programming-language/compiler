## The private std::os::OsArena is visible from this descendant module by Modules §3.
bad := fn() -> std::os::OsArena {
  return std::os::arena(4096)
}
