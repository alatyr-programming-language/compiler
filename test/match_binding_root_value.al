Row := struct { pad : u64, a : Mid }
Mid := struct { head : u64, arr : [u64; 3] }
Opt := enum { None, Some([Row; 2]) }

main := fn() -> u64 {
  o := Opt.Some([Row(pad = 7, a = Mid(head = 11, arr = [10, 20, 30])), Row(pad = 13, a = Mid(head = 17, arr = [40, 50, 60]))])
  return match o {
    Opt::Some(xs) => { xs[1].a.arr[2] + xs[0].a.arr[1] }
    Opt::None => { 0 }
  }
}
