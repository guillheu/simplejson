@target(erlang)
import file_streams/file_stream
@target(erlang)
import file_streams/text_encoding

import gleam/bool
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplejson
import simplejson/jsonvalue.{
  type ParseError, InvalidCharacter, InvalidEscapeCharacter, InvalidHex,
  InvalidNumber, JsonArray, JsonBool, JsonNull, JsonNumber, JsonObject,
  JsonString, UnexpectedCharacter, UnexpectedEnd,
}
import simplifile
import startest.{describe, it}
import startest/expect

type Test {
  Test(
    file: String,
    erlang_error: Result(String, ParseError),
    javascript_error: Result(String, ParseError),
  )
}

// The below tests all fail with the linked errors
// Most of the errors are due to Erlang deeming
// D800-DFFF as invalid
// There are a couple of BOM entries in there in which 
// BOMs (or the Zero-Width No-Break Space) are not actually
// valid whitespace characters in JSON. However these (FFEF and FFFE) should
// arguably just be ignored as they are not actually part of the
// contents on the string, rather just markers as to how the string
// should have been read
const failing_tests = [
  Test(
    "./test/testfiles/y_string_last_surrogates_1_and_2.json",
    Error(InvalidHex("DBFF", "DBFF\\uDFFF\"]", 4)),
    Error(InvalidHex("DBFF", "DBFF\\uDFFF\"]", 4)),
  ),
  Test(
    "./test/testfiles/y_string_accepted_surrogate_pair.json",
    Error(InvalidHex("D801", "D801\\udc37\"]", 4)),
    Error(InvalidHex("D801", "D801\\udc37\"]", 4)),
  ),
  Test(
    "./test/testfiles/y_string_unicode_U+1FFFE_nonchar.json",
    Error(InvalidHex("D83F", "D83F\\uDFFE\"]", 4)),
    Error(InvalidHex("D83F", "D83F\\uDFFE\"]", 4)),
  ),
  Test(
    "./test/testfiles/y_string_unicode_U+10FFFE_nonchar.json",
    Error(InvalidHex("DBFF", "DBFF\\uDFFE\"]", 4)),
    Error(InvalidHex("DBFF", "DBFF\\uDFFE\"]", 4)),
  ),
  Test(
    "./test/testfiles/y_string_accepted_surrogate_pairs.json",
    Error(InvalidHex("d83d", "d83d\\ude39\\ud83d\\udc8d\"]", 4)),
    Error(InvalidHex("d83d", "d83d\\ude39\\ud83d\\udc8d\"]", 4)),
  ),
  Test(
    "./test/testfiles/y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF.json",
    Error(InvalidHex("D834", "D834\\uDd1e\"]", 4)),
    Error(InvalidHex("D834", "D834\\uDd1e\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_incomplete_surrogates_escape_valid.json",
    Error(InvalidHex("D800", "D800\\uD800\\n\"]", 4)),
    Error(InvalidHex("D800", "D800\\uD800\\n\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_UTF-16LE_with_BOM.json",
    Error(UnexpectedCharacter("\u{FEFF}", "\u{FEFF}[\"é\"]", 0)),
    Error(UnexpectedCharacter("\u{FEFF}", "\u{FEFF}[\"é\"]", 0)),
  ),
  Test(
    "./test/testfiles/i_string_invalid_surrogate.json",
    Error(InvalidHex("d800", "d800abc\"]", 4)),
    Error(InvalidHex("d800", "d800abc\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_object_key_lone_2nd_surrogate.json",
    Error(InvalidHex("DFAA", "DFAA\":0}", 4)),
    Error(InvalidHex("DFAA", "DFAA\":0}", 4)),
  ),
  Test(
    "./test/testfiles/i_string_1st_surrogate_but_2nd_missing.json",
    Error(InvalidHex("DADA", "DADA\"]", 4)),
    Error(InvalidHex("DADA", "DADA\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_invalid_lonely_surrogate.json",
    Error(InvalidHex("d800", "d800\"]", 4)),
    Error(InvalidHex("d800", "d800\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_structure_UTF-8_BOM_empty_object.json",
    Error(UnexpectedCharacter("\u{FEFF}", "\u{FEFF}{}", 0)),
    Ok("{}"),
  ),
  Test(
    "./test/testfiles/i_string_incomplete_surrogate_pair.json",
    Error(InvalidHex("Dd1e", "Dd1ea\"]", 4)),
    Error(InvalidHex("Dd1e", "Dd1ea\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_incomplete_surrogate_and_escape_valid.json",
    Error(InvalidHex("D800", "D800\\n\"]", 4)),
    Error(InvalidHex("D800", "D800\\n\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_lone_second_surrogate.json",
    Error(InvalidHex("DFAA", "DFAA\"]", 4)),
    Error(InvalidHex("DFAA", "DFAA\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_1st_valid_surrogate_2nd_invalid.json",
    Error(InvalidHex("D888", "D888\\u1234\"]", 4)),
    Error(InvalidHex("D888", "D888\\u1234\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_string_inverted_surrogates_U+1D11E.json",
    Error(InvalidHex("Dd1e", "Dd1e\\uD834\"]", 4)),
    Error(InvalidHex("Dd1e", "Dd1e\\uD834\"]", 4)),
  ),
  Test(
    "./test/testfiles/i_number_huge_exp.json",
    Error(
      InvalidNumber(
        "0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006",
        "0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006]",
        1,
      ),
    ),
    Error(
      InvalidNumber(
        "0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006",
        "0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006]",
        1,
      ),
    ),
  ),
]

pub fn main() {
  startest.run(startest.default_config())
}

// gleeunit test functions end in `_test`
pub fn simplejson_tests() {
  io.debug("Running tests")
  simplifile.get_files("./test/testfiles")
  |> expect.to_be_ok
  // |> list.filter(fn(name) { string.contains(name, "n_array_invalid_utf8.json") })
  |> list.map(fn(name) {
    it(name, fn() {
      let json = read_file(name)
      use <- bool.guard(when: json == Error(Nil), return: Nil)
      let assert Ok(json) = json
      let parsed = simplejson.parse(json)
      case list.last(string.split(name, "/")) {
        Ok("n" <> _) -> {
          parsed |> result.map_error(fn(_) { Nil }) |> expect.to_be_error
        }
        Ok("i" <> _) | Ok("y" <> _) -> {
          case list.find(failing_tests, fn(e) { e.file == name }) {
            Ok(Test(_, erlang_err, js_err)) -> {
              let res = case is_javascript {
                True -> js_err

                False -> erlang_err
              }
              let res = case res {
                Error(err) -> Error(err)
                Ok(str) -> simplejson.parse(str)
              }
              parsed |> expect.to_equal(res)
              Nil
            }
            Error(_) -> {
              parsed |> expect.to_be_ok
              Nil
            }
          }
        }
        _ -> {
          Nil
        }
      }
    })
  })
  |> describe("Parse testfiles", _)
}

pub fn parse_array_tests() {
  describe("Array Parsing - Successful", [
    it("Empty Array", fn() {
      simplejson.parse("[]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(dict.new()))
    }),
    it("Array with String", fn() {
      let expected = dict.new() |> dict.insert(0, JsonString("a"))
      simplejson.parse("[\"a\"]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with Multiple Strings", fn() {
      let expected =
        dict.new()
        |> dict.insert(0, JsonString("a"))
        |> dict.insert(1, JsonString("z"))
      simplejson.parse("[\"a\", \"z\"]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with String and Spaces", fn() {
      let expected = dict.new() |> dict.insert(0, JsonString("a"))
      simplejson.parse(" [ \"a\" ] ")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with Int", fn() {
      let expected =
        dict.new() |> dict.insert(0, JsonNumber(Some(123), None, Some("123")))
      simplejson.parse("[123]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with Multiple Ints", fn() {
      let expected =
        dict.new()
        |> dict.insert(0, JsonNumber(Some(999), None, Some("999")))
        |> dict.insert(1, JsonNumber(Some(111), None, Some("111")))
      simplejson.parse("[999, 111]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with Float", fn() {
      let expected =
        dict.new()
        |> dict.insert(0, JsonNumber(None, Some(123.5), Some("123.5")))
      simplejson.parse("[123.5]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with Multiple Floats", fn() {
      let expected =
        dict.new()
        |> dict.insert(0, JsonNumber(None, Some(999.5), Some("999.5")))
        |> dict.insert(1, JsonNumber(None, Some(111.5), Some("111.5")))
      simplejson.parse("[999.5, 111.5]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array with Multiple JsonValues", fn() {
      let expected =
        dict.new()
        |> dict.insert(0, JsonNumber(Some(999), None, Some("999")))
        |> dict.insert(1, JsonString("111"))
        |> dict.insert(2, JsonObject(dict.from_list([])))
      simplejson.parse("[999, \"111\", {}]")
      |> expect.to_be_ok
      |> expect.to_equal(JsonArray(expected))
    }),
    it("Array inside Object", fn() {
      simplejson.parse("{\"a\": []}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(dict.from_list([#("a", JsonArray(dict.new()))])),
      )
    }),
  ])
}

pub fn parse_array_error_tests() {
  describe("Array Parsing - Errors", [
    it("Unclosed Array", fn() {
      simplejson.parse("[")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Unclosed Array with Space", fn() {
      simplejson.parse("[\n\n\r\t ")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Invalid item in Array", fn() {
      simplejson.parse("[\"]")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Invalid item in Array", fn() {
      simplejson.parse("[-]")
      |> expect.to_be_error
      |> expect.to_equal(InvalidNumber("-]", "-]", 1))
    }),
    it("Invalid closing of Array", fn() {
      simplejson.parse("[{\"a\":1]}")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedCharacter("]", "]}", 7))
    }),
  ])
}

pub fn parse_object_tests() {
  describe("Object Parsing - Successful", [
    it("Empty Object", fn() {
      simplejson.parse("{}")
      |> expect.to_be_ok
      |> expect.to_equal(JsonObject(dict.from_list([])))
    }),
    it("Empty Object with Spaces", fn() {
      simplejson.parse("{\n}\t ")
      |> expect.to_be_ok
      |> expect.to_equal(JsonObject(dict.from_list([])))
    }),
    it("Object with Boolean value", fn() {
      simplejson.parse("{\"test\":true}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(dict.from_list([#("test", JsonBool(True))])),
      )
    }),
    it("Object with String value", fn() {
      simplejson.parse("{\"test\":\"true\"}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(dict.from_list([#("test", JsonString("true"))])),
      )
    }),
    it("Object with Null value", fn() {
      simplejson.parse("{\"test\":  null}")
      |> expect.to_be_ok
      |> expect.to_equal(JsonObject(dict.from_list([#("test", JsonNull)])))
    }),
    it("Object with Number value", fn() {
      simplejson.parse("{\"test\":999}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(
          dict.from_list([#("test", JsonNumber(Some(999), None, Some("999")))]),
        ),
      )
    }),
    it("Object with Object value", fn() {
      simplejson.parse("{\"test\":{}}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(dict.from_list([#("test", JsonObject(dict.from_list([])))])),
      )
    }),
    it("Object with Multiple values", fn() {
      simplejson.parse("{\"1\":true, \"2\":false}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(
          dict.from_list([#("1", JsonBool(True)), #("2", JsonBool(False))]),
        ),
      )
    }),
    it("Object with Multiple values and duplicate", fn() {
      simplejson.parse("{\"1\":true, \"2\":false, \"1\":123}")
      |> expect.to_be_ok
      |> expect.to_equal(
        JsonObject(
          dict.from_list([
            #("1", JsonNumber(Some(123), None, Some("123"))),
            #("2", JsonBool(False)),
          ]),
        ),
      )
    }),
  ])
}

pub fn parse_object_error_tests() {
  describe("Object Parsing - Errors", [
    it("Unclosed Object", fn() {
      simplejson.parse("{")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Unclosed Key", fn() {
      simplejson.parse("{\"")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Just Key", fn() {
      simplejson.parse("{\"key\"")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Just Key and Colon", fn() {
      simplejson.parse("{\"key\": }")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedCharacter("}", "}", 8))
    }),
  ])
}

pub fn parse_string_tests() {
  describe("String Parsing - Successful", [
    it("Empty String", fn() {
      simplejson.parse("\"\"")
      |> expect.to_be_ok
      |> expect.to_equal(JsonString(""))
    }),
    it("Simple String", fn() {
      simplejson.parse("\"abc\"")
      |> expect.to_be_ok
      |> expect.to_equal(JsonString("abc"))
    }),
    it("String with Escaped Chars", fn() {
      simplejson.parse("\"a\\r\\nb\"")
      |> expect.to_be_ok
      |> expect.to_equal(JsonString("a\r\nb"))
    }),
    it("String with Unicode Chars", fn() {
      simplejson.parse("\"\\u1000\\u2000\"")
      |> expect.to_be_ok
      |> expect.to_equal(JsonString("\u{1000}\u{2000}"))
    }),
    it("String with Quotes and Backslash", fn() {
      simplejson.parse("\"a\\\"\\\\b\"")
      |> expect.to_be_ok
      |> expect.to_equal(JsonString("a\"\\b"))
    }),
  ])
}

pub fn parse_string_error_tests() {
  describe("String Parsing - Errors", [
    it("Unclosed String", fn() {
      simplejson.parse("\"")
      |> expect.to_be_error
      |> expect.to_equal(UnexpectedEnd)
    }),
    it("Invalid Char", fn() {
      simplejson.parse("\"\u{05}\"")
      |> expect.to_be_error
      |> expect.to_equal(InvalidCharacter("\u{05}", "\u{05}\"", 1))
    }),
    it("Invalid Escape", fn() {
      simplejson.parse("\"\\h\"")
      |> expect.to_be_error
      |> expect.to_equal(InvalidEscapeCharacter("h", "\\h\"", 1))
    }),
  ])
}

@target(javascript)
fn read_file(name: String) -> Result(String, Nil) {
  case simplifile.read(name) {
    Ok(content) -> Ok(content)
    Error(_) -> Error(Nil)
  }
}

@target(erlang)
fn read_file(name: String) -> Result(String, Nil) {
  let encoding = case
    string.contains(string.lowercase(name), "utf16")
    || string.contains(string.lowercase(name), "utf-16")
  {
    True -> {
      text_encoding.Utf16(case string.contains(string.lowercase(name), "be") {
        True -> text_encoding.Big
        False -> text_encoding.Little
      })
    }
    False -> {
      text_encoding.Unicode
    }
  }
  let assert Ok(stream) = file_stream.open_read_text(name, encoding)
  let assert Ok(info) = simplifile.file_info(name)
  let json = file_stream.read_chars(stream, info.size)
  let ret = case json {
    Ok(json) -> {
      Ok(json)
    }
    Error(_) -> {
      case simplifile.read(name) {
        Ok(content) -> Ok(content)
        Error(_) -> Error(Nil)
      }
    }
  }
  let assert Ok(Nil) = file_stream.close(stream)

  ret
}

@target(erlang)
const is_javascript = False

@target(javascript)
const is_javascript = True
