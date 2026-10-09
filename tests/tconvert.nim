# Unit tests for the AST -> TypeScript mapping. They run at compile time,
# because NimNodes only exist there: if this file compiles, the tests pass.

import std/macros
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
  doAssert decl("type Empty = object") == "export interface Empty {}"
  doAssert decl("type P = object\n  x, y: float") ==
    "export interface P {\n  x: number;\n  y: number;\n}"
