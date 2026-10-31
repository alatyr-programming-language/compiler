## A direct standard I/O call in a function's trailing expression is still a
## freestanding violation; the contract must not depend on statement-vs-tail form.
@limits(freestanding)
emit := fn() -> isize { std::io::print("") }
main := fn() -> u64 {
  emit()
  42
}
## expect: reject "@limits(freestanding) violation" "at line 4"
