## A file contract equal to the manifest ceiling is valid and remains runnable/testable.
@limits(no_unchecked, no_alloc)
main := fn() -> u64 { 42 }
@test("manifest ceiling equality") fn() {}
