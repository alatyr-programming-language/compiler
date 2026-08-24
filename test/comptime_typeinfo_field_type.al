## CT-6: Field.type is a comptime type value. Each backend must preserve the
## current field's declared type when the field derive supplies it as a generic
## type argument; this mixed-width pair catches reuse of the enclosing struct
## type or the first field's type.
S := struct { wide : u64, narrow : u32 }

sum_fields := fn(T : type, value : T) -> u64 {
  comptime if (match typeinfo(T) { Struct(_) => true; _ => false }) {
    mut total : u64 = 0
    comptime for f in typeinfo(T).fields {
      total = total + sum_fields(f.type, value.(f))
    }
    return total
  } else {
    return u64(value)
  }
}

main := fn() -> u64 { sum_fields(S, S(wide = 40, narrow = 2)) }
