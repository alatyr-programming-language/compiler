## Issue #1744, review of PR #1748 (B2): callees from another module whose signatures spell only names
## declared once, but REACH a name both modules declare: `T` aliases `Inner`, a `Box` field and an `E`
## payload after the first are `Word`. The IR builder lays a callee's signature types out from the
## caller's module (#1734), so it must follow the alias, the field and the payload list, and refuse each
## call by its named cause (`alatyr ir --modules`, the check in scripts/e2e.sh). The three callers read
## no field of `m`'s values, so x86_64's legacy path answers right on both sides of the fix (a field read
## of `m::mk()` in the root is the legacy defect #1734 itself, fixed by #1743, and is not measured here).
## NON-VACUOUS: on the PR's first head 0f90e2a9 `main::use` was Built; and the review's probe, which
## reads `t.a + t.b` of `m::mk()` against the root's three-word `Inner`, answered a different value on
## each x86_64 run through the IR-built caller.
## Expected exit 42: 42 from `m::sum(m::mk())`, 7 from the box, 9 from the payload, less 16.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "issue1744-sig-alias-ir",
    ),
  ],
)
## expect: run 42
