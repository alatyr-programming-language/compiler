## e2e — Comptime §9.2 / Tooling §2.7: a `comptime if` on `target.arch` must honour the OPERATOR.
## The x86 lower's arch fold read only the RHS `Arch.<name>` and returned the `==` answer for BOTH
## `==` and `!=`, so `target.arch != Arch.x86_64` selected the THEN branch on an x86_64 build — a
## silent WRONG-BRANCH miscompile, and a disagreement with `sema::guard_fold` / `a64_comp_cond_fold` /
## `rv_comp_cond_fold` / `wat_comp_cond_fold`, all of which already branch on `op == 20`/`op == 28`.
##
## ARCH-NEUTRAL by construction: the RHS is `Arch.i386`, an arch NO backend in this corpus emits, so
## `==` is FALSE and `!=` TRUE on every target alike — the operator, not the target, decides. (The
## file used to spell `Arch.x86_64`/`Arch.aarch64`, which only summed to 42 while every backend
## pretended `target.arch` was x86_64; the machine each backend actually names is pinned by
## `when_guard_arch`.) If the fold ignores the operator and answers `==` for both, `f` takes its ELSE
## (0), `g` its ELSE (20) and `h` its ELSE (0) → 20, not 42.
f := fn() -> u64 { comptime if target.arch != Arch.i386 { return 20 } else { return 0 } }
g := fn() -> u64 { comptime if target.arch == Arch.i386 { return 0 } else { return 20 } }
h := fn() -> u64 { comptime if target.arch != Arch.i386 { return 2 } else { return 0 } }
main := fn() -> u64 {
  return f() + g() + h()
}
