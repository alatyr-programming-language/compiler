## Regression for #169: a by-value standard-byte struct parameter must preserve
## its second narrow field. This reads only b so a first-field-only pass cannot hide it.

T := struct { a : u8, b : u8 }
take_second := fn(s : T) -> u64 { u64(s.b) }

main := fn() -> u64 {
  take_second(T(a = 7, b = 5))
}
