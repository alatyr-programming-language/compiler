## Issue #1808 — an alias whose right-hand side applies a type constructor names the type it builds. Two
## modules each declare `Node` (different field orders) and six aliases with the same names over
## different arguments: `P` is `m::Box(u8)` in the root and `Box(u64)` in `m`, `Q` is `ptr(Node)` over
## each module's own `Node`, `R` is `uint(8)` and `uint(64)`, `S` is `m::Box(Node)` over each `Node`.
## `F(A)` and `F(B)` are distinct types (Types §4.1), so each pair is two instances of `m::tag`
## (Comptime §3.2). `U := (Node, u64)` and `V := [Node; 2]` are not followed to what they name, so each
## module's alias is identified by its own declaration: two instances again. The e2e row pins the twelve
## symbols. Before the fix each pair collapsed into one instance by its text (`m__tag__P`, …), laid out
## for whichever spelling registered it first. `tag` ignores its type's layout, so the program answers
## 42 either way: the symbols are the assertion.
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
      output = "issue1808-alias-call-instance",
    ),
  ],
)
## spec: Types §4.1; Comptime §3.2; Declarations §1.3
## expect: run 42
