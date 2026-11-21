## #1466 / Functions §2.3: a statement call to a function declared later, omitting its `in out`
## parameter. It used to build and crash (139) writing through a null place.
main := fn() -> u64 {
  set(7)
  return 42
}
set := fn(x : u64, in out y : u64) { y = x }
## expect: reject "leaves parameter `y` unbound" "at line 4"
