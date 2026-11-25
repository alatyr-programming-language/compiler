- **A name a module binds by an alias `f := other::f` or a listed projection `(f) := other` shadows an
  ancestor module's `f` in that module and its descendants (#1915, Declarations §6.1).** A bare call
  `f(40)` in `geo::child` called `geo`'s own `f` instead (140 where 42 was due), a generic `f` alike, and
  `check` judged the arguments against `geo`'s signature, refusing a valid call. A call through a
  shadowing alias that renames a generic function (`f := other::h`) is refused at the call with a
  located diagnostic until #1920 instantiates it, rather than failing at the linker. PATCH.
