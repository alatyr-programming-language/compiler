## CT-6: each typeinfo field exposes its byte offset.
S := struct { x : u64, y : u64, z : u64 }
P := @packed struct { a : u8, b : u32, c : u16 }
B := struct { data : [u8; 4], tail : u16 }

sum_offsets := fn(T : type) -> u64 {
  mut total : u64 = 0
  comptime for f in typeinfo(T).fields { total = total + f.offset }
  total
}

main := fn() -> u64 { sum_offsets(S) + sum_offsets(P) + sum_offsets(B) }
