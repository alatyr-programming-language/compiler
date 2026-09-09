## Issue #304 controls — correct scalar stores through annotated Slice(T) places remain valid.
write_u64 := fn(in out s : Slice(u64)) { s[0] = 40 }
write_bool := fn(in out s : Slice(bool)) { s[0] = true }

main := fn() -> u64 {
  ## This slice proves semantic acceptance on every backend. Keep the stores in a checked body without
  ## executing them: value-preserving slice writes have architecture-specific coverage under #213.
  if false {
    mut ints : [u64; 2] = [1, 2]
    mut flags : [bool; 1] = [false]
    mut local : Slice(u64) = ints[0..2]
    local[1] = 2
    int_view := ints[0..2]
    bool_view := flags[0..1]
    write_u64(int_view)
    write_bool(bool_view)
  }
  42
}
