import gleam/bool
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub fn main() {
  io.println("Hello from simplejson!")
  parse("123")
  parse("-123")
  parse("-")
  parse("123.234")
  parse("-123.123")
  parse("123e1")
  parse("-123e+2")
  parse("123e-3")
  parse("-123.123e1")
  parse("123.02e-1")
  parse("-123.45e+1")
  parse("-123.123e3")
  parse("-12300e-3")
  parse("[]")
  parse("[1]")
  parse("[1,2]")
  parse("[1, 2]")

  parse("[1, 2, \"\"]")
  parse("[1, 2, \"testing!!\"]")
  parse("[1, 2, \"\\\"\"]")
  parse("[1, 2, \"\\u0041\\\\\\/\"]")
  parse("[1, 2, -134.5e-10]")
  parse("[1, 2, \"\"\"]")
  parse("[1, 2, \"\"\"\"]")
  parse("[1")
  // parse("[1 , 2, 3]")
}

pub type JsonValue {
  JsonString(str: String)
  JsonNumber(int: Option(Int), float: Option(Float))
  JsonBool(bool: Bool)
  JsonNull
  JsonArray(List(JsonValue))
}

pub fn parse(json: String) -> JsonValue {
  do_parse(json)
  |> result.unwrap(#("XXX", JsonString("ARGH")))
  |> io.debug

  JsonNull
}

fn do_parse(json: String) -> Result(#(String, JsonValue), Nil) {
  case json {
    "[" <> rest -> {
      do_parse_list(rest, [], None)
    }
    "\"" <> rest -> {
      do_parse_string(rest, "")
    }
    " " <> rest | "\r" <> rest | "\n" <> rest | "\t" <> rest -> {
      do_parse(rest)
    }
    "-" <> _rest
    | "0" <> _rest
    | "1" <> _rest
    | "2" <> _rest
    | "3" <> _rest
    | "4" <> _rest
    | "5" <> _rest
    | "6" <> _rest
    | "7" <> _rest
    | "8" <> _rest
    | "9" <> _rest -> {
      do_parse_number(json)
    }

    _ -> Error(Nil)
  }
}

fn do_parse_string(
  json: String,
  str: String,
) -> Result(#(String, JsonValue), Nil) {
  use #(char, rest) <- result.try(string.pop_grapheme(json))
  case char {
    "\"" -> Ok(#(rest, JsonString(str)))
    "\\" -> {
      case rest {
        "\"" <> rest -> do_parse_string(rest, str <> "\"")
        "\\" <> rest -> do_parse_string(rest, str <> "\\")
        "/" <> rest -> do_parse_string(rest, str <> "/")
        "b" <> rest -> do_parse_string(rest, str <> "\u{08}")
        "f" <> rest -> do_parse_string(rest, str <> "\f")
        "n" <> rest -> do_parse_string(rest, str <> "\n")
        "r" <> rest -> do_parse_string(rest, str <> "\r")
        "t" <> rest -> do_parse_string(rest, str <> "\t")
        "u" <> rest -> {
          use #(rest, char) <- result.try(parse_hex(rest))
          do_parse_string(rest, str <> char)
        }
        _ -> Error(Nil)
      }
    }
    _ -> do_parse_string(rest, str <> char)
  }
}

fn parse_hex(json: String) -> Result(#(String, String), Nil) {
  let hex = string.slice(json, 0, 4)
  use <- bool.guard(string.length(hex) < 4, return: Error(Nil))
  let rest = string.drop_left(json, 4)

  use parsed <- result.try(int.base_parse(hex, 16))
  use utf8 <- result.try(string.utf_codepoint(parsed))

  Ok(#(rest, string.from_utf_codepoints([utf8])))
}

fn do_parse_list(
  json: String,
  list: List(JsonValue),
  last_value: Option(JsonValue),
) -> Result(#(String, JsonValue), Nil) {
  case json {
    "]" <> rest -> Ok(#(rest, JsonArray(list.reverse(list))))
    "," <> rest -> {
      case last_value {
        None -> Error(Nil)
        Some(_) -> {
          use #(rest, next_item) <- result.try(do_parse(rest))
          do_parse_list(rest, [next_item, ..list], Some(next_item))
        }
      }
    }
    _ -> {
      case last_value {
        None -> {
          use #(rest, next_item) <- result.try(do_parse(json))
          do_parse_list(rest, [next_item, ..list], Some(next_item))
        }
        Some(_) -> Error(Nil)
      }
    }
  }
}

fn do_parse_number(json: String) -> Result(#(String, JsonValue), Nil) {
  use #(json, num) <- result.try(case json {
    "-" <> rest -> {
      do_parse_int(rest, "-")
    }
    _ -> do_parse_int(json, "")
  })

  use #(json, fraction) <- result.try(case json {
    "." <> rest -> do_parse_int(rest, "")
    _ -> Ok(#(json, ""))
  })

  use #(json, exp) <- result.try(case json {
    "e" <> rest | "E" <> rest -> do_parse_exponent(rest)
    _ -> Ok(#(json, ""))
  })

  let ret = case fraction {
    "" -> {
      case exp {
        "" -> JsonNumber(Some(decode_int(num, "", 0)), None)

        "-" <> exp -> {
          let assert Ok(exp) = int.parse(exp)
          case string.ends_with(num, string.repeat("0", exp)) {
            True -> JsonNumber(Some(decode_int(num, "", -exp)), None)
            False -> JsonNumber(None, Some(decode_float(num, fraction, -exp)))
          }
        }
        "+" <> exp | exp -> {
          let assert Ok(exp) = int.parse(exp)
          JsonNumber(Some(decode_int(num, "", exp)), None)
        }
      }
    }
    _ -> {
      case exp {
        "" -> JsonNumber(None, Some(decode_float(num, fraction, 0)))
        "-" <> exp -> {
          let assert Ok(exp) = int.parse(exp)
          JsonNumber(None, Some(decode_float(num, fraction, -exp)))
        }
        "+" <> exp | exp -> {
          let assert Ok(exp) = int.parse(exp)
          case exp >= string.length(fraction) {
            True -> JsonNumber(Some(decode_int(num, fraction, exp)), None)
            False -> JsonNumber(None, Some(decode_float(num, fraction, exp)))
          }
        }
      }
    }
  }

  Ok(#(json, ret))
}

fn decode_int(int_val: String, fraction: String, exp: Int) -> Int {
  let assert Ok(int_val) = int.parse(int_val)

  let int_val = case exp < 0 {
    True -> {
      let assert Ok(mult) = int.power(10, int.to_float(-exp))
      int_val / float.truncate(mult)
    }
    False -> {
      let assert Ok(mult) = int.power(10, int.to_float(exp))
      int_val * float.truncate(mult)
    }
  }

  case fraction {
    "" -> int_val
    _ -> {
      let assert Ok(fraction) = int.parse(fraction)
      let fraction = case int_val < 0 {
        True -> -fraction
        False -> fraction
      }
      int_val + fraction
    }
  }
}

fn decode_float(int_val: String, fraction: String, exp: Int) -> Float {
  let float_val = case fraction {
    "" -> int_val <> ".0"
    _ -> int_val <> "." <> fraction
  }
  let assert Ok(float_val) = float.parse(float_val)
  let assert Ok(mult) = int.power(10, int.to_float(exp))

  float_val *. mult
}

fn do_parse_exponent(json: String) -> Result(#(String, String), Nil) {
  use #(json, exp) <- result.try(case json {
    "+" <> rest -> do_parse_int(rest, "")
    "-" <> rest -> do_parse_int(rest, "-")
    _ -> do_parse_int(json, "")
  })

  Ok(#(json, exp))
}

fn do_parse_int(json: String, num: String) -> Result(#(String, String), Nil) {
  case json {
    "0" as n <> rest
    | "1" as n <> rest
    | "2" as n <> rest
    | "3" as n <> rest
    | "4" as n <> rest
    | "5" as n <> rest
    | "6" as n <> rest
    | "7" as n <> rest
    | "8" as n <> rest
    | "9" as n <> rest -> {
      do_parse_int(rest, num <> n)
    }
    _ -> {
      case num {
        "" | "-" -> Error(Nil)
        _ -> Ok(#(json, num))
      }
    }
  }
}
// fn parse_array(json: String, acc: JsonValue) -> JsonValue {

// }
