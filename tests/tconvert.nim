# Unit tests for the AST -> TypeScript mapping. They run at compile time,
# because NimNodes only exist there: if this file compiles, the tests pass.

import std/[macros, tables]
import nim2ts/convert

static:
  # Type expressions
  doAssert toTsType(parseExpr("string")) == "string"
  doAssert toTsType(parseExpr("int64")) == "number"
  doAssert toTsType(parseExpr("bool")) == "boolean"
  doAssert toTsType(parseExpr("User")) == "User"
  doAssert toTsType(parseExpr("seq[int]")) == "number[]"
  doAssert toTsType(parseExpr("array[3, bool]")) == "boolean[]"
  doAssert toTsType(parseExpr("Option[string]")) == "string | null"
  doAssert toTsType(parseExpr("seq[Option[int]]")) == "(number | null)[]"
  doAssert toTsType(parseExpr("Table[string, User]")) == "Record<string, User>"
  doAssert toTsType(parseExpr("Page[User]")) == "Page<User>"
  doAssert toTsType(parseExpr("ref User")) == "User"

  # Whole declarations: parseStmt gives a type section, [0] is the nnkTypeDef.
  proc decl(src: string): string = toTsDecl(parseStmt(src)[0][0]).code

  doAssert decl("type Id = distinct int") == "export type Id = number;"
  doAssert decl("type Role = enum admin, member") ==
    "export type Role = \"admin\" | \"member\";"
  doAssert decl("type Empty = object") == "export type Empty = {};"
  doAssert decl("type P = object\n  x, y: float") ==
    "export type P = {\n  x: number;\n  y: number;\n};"
  doAssert decl("type C = object of Base\n  x: int") ==
    "export type C = Base & {\n  x: number;\n};"
  doAssert decl("type C = ref object of Base") == "export type C = Base;"
  doAssert decl("type P = object\n  a* {.omitNone.}, b: Option[int]") ==
    "export type P = {\n  a?: number;\n  b: number | null;\n};"

# Case objects need the wire values of their discriminator enum.
const enums = {
  "Kind": @[("circle", "circle"), ("rect", "RECT"), ("dot", "dot")],
}.toTable

static:
  proc variant(src: string): string = toTsDecl(parseStmt(src)[0][0], enums).code

  doAssert variant("""
type S = object
  name: string
  case kind: Kind
  of circle: r: float
  of rect:
    w, h: float
    label: string
  of dot: discard""") == """export type S = {
  name: string;
} & (
  | { kind: "circle"; r: number }
  | { kind: "RECT"; w: number; h: number; label: string }
  | { kind: "dot" }
);"""

  doAssert variant("""
type S = object of Base
  case kind: Kind
  of circle, dot: r: float
  else: discard""") == """export type S = Base & (
  | { kind: "circle" | "dot"; r: number }
  | { kind: "RECT" }
);"""

  doAssert variant("""
type S[T] = object
  case on: bool
  of true: value: T
  of false: discard
  case kind: Kind
  of rect: discard
  else: n: int""") == """export type S<T> = (
  | { on: true; value: T }
  | { on: false }
) & (
  | { kind: "RECT" }
  | { kind: "circle" | "dot"; n: number }
);"""

macro convert(src: static string) =
  discard toTsDecl(parseStmt(src)[0][0], enums)

doAssert compiles(convert("type S = object\n  case k: Kind\n  of circle: discard\n  else: discard"))
# Unsupported shapes are compile errors.
doAssert not compiles(convert("type E = enum a = \"same\", b = \"same\""))
doAssert not compiles(convert("type S = object\n  a {.omitNone.}: int"))
doAssert not compiles(convert("type S = object\n  t: Table[int, string]"))
doAssert not compiles(convert("type S = object\n  p: ptr int"))
doAssert not compiles(convert("type S = object\n  case k: Unknown\n  of a: discard"))
doAssert not compiles(convert("type S = object\n  case k: int\n  of 1: discard"))
doAssert not compiles(convert("type S = object\n  case k: Kind\n  of square: discard"))
doAssert not compiles(convert("type S = object\n  case k: Kind\n  of circle..rect: discard"))
doAssert not compiles(convert("""
type S = object
  case k: Kind
  of circle:
    case on: bool
    of true: discard
    of false: discard
  else: discard"""))
