## e2e (x86 only) — the second SILENTLY WRONG shape of the statement-vs-value `if` classifier defect
## (I11): a chain as the last statement of a statement-`match` arm. Taken for a tail value expression,
## the misparse bound the wrong condition to the wrong body — the base compiler compiled this clean and
## ran the MIDDLE arm where the terminal `else` was the true one. Every arm of both chains gets a
## distinct result, so a branch taken in error cannot pass. Returns 42; a mismatch returns 60 + a
## bitmask of the disagreeing inputs.
## x86 only for a reason that has nothing to do with the chain: a statement `match` over integer
## literals whose arm bodies assign a local already traps under qemu-aarch64/riscv64 (133) and
## wasmtime (134). Measured identical on the base compiler for the same three-arm match with no chain
## in it at all, so this is the pre-existing cross-backend match gap, not this fixture's construct —
## the portable half of the same defect is `if_chain_nested_else_tail`.
mut R := 0
setr := fn(x : u64) -> u64 { R = x ; return x }
in_match_arm := fn(n : u64) -> u64 {
  R = 0
  match n {
    0 => { if n == 7 { setr(7) } else if n == 0 { R = 11 } else { R = 12 } }
    1 => { if n == 7 { setr(7) } else if n == 0 { R = 13 } else { R = 14 } }
    _ => { R = 15 }
  }
  return R
}
main := fn() -> u64 {
  mut bad := 0
  if in_match_arm(0) != 11 { bad = bad + 1 }
  if in_match_arm(1) != 14 { bad = bad + 2 }
  if in_match_arm(3) != 15 { bad = bad + 4 }
  if bad != 0 { return 60 + bad }
  return 42
}
