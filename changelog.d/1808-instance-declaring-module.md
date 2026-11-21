- **A generic instantiated at two same-named types from different modules is two instances (#1808,
  #1810).** On x86_64 a program that called one generic at `m::Node` and at the root module's own
  `Node` read the root's struct with `m`'s layout: 2 where the program says 40, with a clean compile.
  The function that read the wrong value called no generic. Comptime §3.2 gives each distinct set of
  type arguments its own instance, and Modules §6.7 makes their symbols distinct. An instance's
  identity and label now come from the module that declares each type argument, so the two instances
  get two symbols (`m__at__m__Node`, `m__at__main__Node`), and a struct named by a qualified path is no
  longer taken for the bare same-named struct. One instance written with different spacing
  (`ptr( u64 )`, `ptr(u64)`) is now emitted once instead of being refused as a duplicate label.
  An alias is the type it names (Declarations §1.3): `A := Node` shares `Node`'s instance, and two
  modules' `A`s over their own `Node`s, or `W := u8` and `W := u64`, are two instances, each reading
  its own layout or width. A brand is its own type (Types §5.4), so two modules' `Id := brand(Node)`
  are two instances too. A qualified `m::A` now names `m`'s alias even where the root declares its
  own `A`, in a plain read as well as in a generic. The same holds when the alias applies a type
  constructor: two modules' `P`s over `m::Box(u8)` and `Box(u64)`, over `ptr(Node)` of each module's
  own `Node`, or over `uint(8)` and `uint(64)` are two instances (Types §4.1), and an alias the
  compiler cannot follow (a tuple or an array) is identified by its own declaration rather than its
  name.
  aarch64, riscv64 and wasm do not yet call a generic in these shapes and still stop at their
  stubs there, a trap rather than a value.
