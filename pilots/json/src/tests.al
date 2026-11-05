## The library's tests (Tooling §4.1): `alatyr test` in this directory.

@test("parses a scalar") fn() {
  r := std::os::arena(65536)
  match r {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      match text::parse(ptr(mut ar), "42") {
        Ok(v) => {
          match v {
            value::Value.Int(n) => {
              if n != 42 { panic("value") }
            }
            _ => {
              panic("variant")
            }
          }
        }
        Err(_) => {
          panic("parse")
        }
      }
      std::os::free(osa)
    }
    Err(_) => {
      panic("arena")
    }
  }
}

@test("locates a trailing comma") fn() {
  r := std::os::arena(65536)
  match r {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      match text::parse(ptr(mut ar), "[1,]") {
        Ok(_) => {
          panic("accepted")
        }
        Err(e) => {
          if e.kind != text::ErrorKind.UnexpectedByte { panic("kind") }
          if e.offset != 3 or e.line != 1 or e.column != 4 { panic("position") }
        }
      }
      std::os::free(osa)
    }
    Err(_) => {
      panic("arena")
    }
  }
}

@test("decodes escapes and a surrogate pair") fn() {
  r := std::os::arena(65536)
  match r {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      match text::parse(ptr(mut ar), "\"a\\tb\\u0041\\ud83d\\ude00\"") {
        Ok(v) => {
          match v {
            value::Value.Str(s) => {
              if s != "a\tbA\xf0\x9f\x98\x80" { panic("text") }
            }
            _ => {
              panic("variant")
            }
          }
        }
        Err(_) => {
          panic("parse")
        }
      }
      std::os::free(osa)
    }
    Err(_) => {
      panic("arena")
    }
  }
}

@test("reads the i64 minimum as an Int") fn() {
  r := std::os::arena(65536)
  match r {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      match text::parse(ptr(mut ar), "-9223372036854775808") {
        Ok(v) => {
          match v {
            value::Value.Int(n) => {
              if n != 0 - 9223372036854775807 - 1 { panic("value") }
            }
            _ => {
              panic("variant")
            }
          }
        }
        Err(_) => {
          panic("parse")
        }
      }
      std::os::free(osa)
    }
    Err(_) => {
      panic("arena")
    }
  }
}
