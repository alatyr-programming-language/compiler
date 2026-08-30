# Lowering ownership map

The lowering path is a shared AST-to-backend pipeline with explicit target seams. The purpose of this
map is to prevent a backend decision from being copied into a second emitter without a conformance
fixture.

## Current ownership

| responsibility | owner |
| --- | --- |
| parsing, AST construction, source spans | `src/lexer.al`, `src/parser.al`, `src/ast.al` |
| name resolution, type/ownership checks, located diagnostics | `src/sema.al`, `src/nameres.al` |
| target and artifact fact folding | `src/lower/ctfold.al`, with the driver publication seam in `src/driver.al` |
| layout, field/variant/array facts | `src/lower_layout.al` |
| shared AST handles, spans, parameter helpers | `src/lower_ctx.al` |
| x86 expression/statement lowering | `src/lower.al` and its extracted `src/lower/*.al` clusters |
| x86 places, assignment, ABI, monomorphization, raw assembly | `src/lower/place.al`, `assign.al`, `abi_c.al`, `mono.al`, `ir.al`, `lower_asm.al` |
| AArch64, RV64, and WAT emission | `src/aarch64.al`, `src/riscv64.al`, `src/wat.al` |

`src/lower.al` is still the largest x86 coordinator, but it is no longer the only location for
unrelated responsibilities: layout and several codegen clusters are already separate modules. New
backend-neutral decisions belong in a shared owner (`ctfold`, `lower_layout`, or `lower_ctx`) before
the target emitter consumes them. A target emitter may add an adapter only for instruction selection,
register assignment, or an ABI-specific representation.

## Status of deferred surfaces

`src/regalloc.al` is an experimental/standalone register-allocation surface with its own self-test; it
is not the production path for the compiler's emitted x86 code. `src/iface.al` is the substrate for a
future interface-aware emit cache; it is not currently a cache authority. Neither may be enabled by a
refactor merely because the module exists. Enabling either requires an explicit decision, byte-level
reproducibility evidence, and a behavior corpus run.

## Refactor contract

Every extraction or centralization must preserve these invariants:

1. one backend-neutral answer for a given layout/ABI/semantic fact;
2. the same located rejection before emission for an unsupported shape;
3. a focused fixture that fails on the parent and checks every claimed backend;
4. `seed → Stage1 → Stage2` fixpoint and the four-backend corpus remain attributable to the same
   source tree;
5. no new source-scan workaround may replace a fact already available in the AST or shared layout
   owner.

The module map's named owners and deferred surfaces are checked mechanically by
`scripts/contract_check.sh`; behavior remains the authority of the compiler and conformance gates.
