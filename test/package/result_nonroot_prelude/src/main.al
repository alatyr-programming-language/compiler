## The root module deliberately has no std/alloc reference. Result is used only
## by the non-root lib module, so package compilation must inject the base prelude
## independently of root imports.
main := fn() -> u64 {
  match lib::go(42) {
    Ok(n) => { return u64(n) }
    Err(_) => { return 1 }
  }
}
