- A struct literal with a path head is now the struct that path names, its named fields bound by name
  (Types §9.3; Modules §4.1, §4.2). `g::S(…)` through a module alias `g := geo` used to take a later
  module's same-named `S` layout on every backend (#1751). `geo::S(b = 2, a = 40)` used to store the
  values in the order they were written (#1929). A path head that names no struct is now refused at the
  literal.
