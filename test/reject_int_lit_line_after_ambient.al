## e2e REJECT + LOCATION (check) — a PARSER-level located reject in a file that also pulls in AMBIENT
## stdlib modules, which is what makes the reported LINE meaningful. The `struct` decl below makes the
## driver inject `lib/base/derive.al` + the base prelude AHEAD of this module in the shared source
## buffer; `parser.al`'s `src_line_at` used to count newlines from that BUFFER base, so this reject —
## on line 12 of a 12-line file — was reported as "line 161". The module name and the quoted snippet
## were right all along, only the number was junk, and every parser-level located reject (all the
## `reject_int_lit_*` / `reject_attr_*` fixtures) inherited it. `src_line_at` now counts from the
## MODULE base (`P_MOD_BASE`, set by the driver before each module's parse), so the number is
## FILE-relative — matching the module name printed beside it.
S := struct { a : u64 }

bad := 0b12
