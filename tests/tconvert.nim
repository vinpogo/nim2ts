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
  proc decl(src: string): string = toTsDecl(parseStmt(src)[0][0])

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
const known = Known(enums: {
  "Kind": @[("circle", "circle"), ("rect", "RECT"), ("dot", "dot")],
}.toTable)

static:
  proc variant(src: string): string = toTsDecl(parseStmt(src)[0][0], known)

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
  discard toTsDecl(parseStmt(src)[0][0], known)

static: doAssert compiles(convert("type S = object\n  case k: Kind\n  of circle: discard\n  else: discard"))
# Unsupported shapes are compile errors.
static: doAssert not compiles(convert("type E = enum a = \"same\", b = \"same\""))
static: doAssert not compiles(convert("type S = object\n  a {.omitNone.}: int"))
static: doAssert not compiles(convert("type S = object\n  t: Table[int, string]"))
static: doAssert not compiles(convert("type S = object\n  p: ptr int"))
static: doAssert not compiles(convert("type S = object\n  case k: Unknown\n  of a: discard"))
static: doAssert not compiles(convert("type S = object\n  case k: int\n  of 1: discard"))
static: doAssert not compiles(convert("type S = object\n  case k: Kind\n  of square: discard"))
static: doAssert not compiles(convert("type S = object\n  case k: Kind\n  of circle..rect: discard"))
static: doAssert not compiles(convert("""
type S = object
  case k: Kind
  of circle:
    case on: bool
    of true: discard
    of false: discard
  else: discard"""))

# RPC procedures
static:
  proc entry(src: string): string = procedureToTs(rpcSignature(parseStmt(src)[0]))

  doAssert entry("proc getUser*(id: UserId): User = discard") ==
    "getUser: { input: { id: UserId }; output: User };"
  doAssert entry("proc find(ctx {.context.}: Ctx, q: string, limit: Option[int]): seq[User] = discard") ==
    "find: { input: { q: string; limit?: number | null }; output: User[] };"
  doAssert entry("proc ping() = discard") ==
    "ping: { input: Record<string, never>; output: null };"
  doAssert entry("proc touch(ctx {.context.}: Ctx): void = discard") ==
    "touch: { input: Record<string, never>; output: null };"

  proc sig(src: string): RpcSignature = rpcSignature(parseStmt(src)[0])
  doAssert clientToTs(@[sig("proc getUser(id: int): User = discard"), sig("proc ping() = discard")]) ==
    """export type Procedures = {
  getUser: { input: { id: number }; output: User };
  ping: { input: Record<string, never>; output: null };
};

export type Transport = <P extends keyof Procedures>(
  procedure: P,
  input: Procedures[P]["input"],
) => Promise<Procedures[P]["output"]>;

export const createClient = (transport: Transport) => ({
  getUser: (input: Procedures["getUser"]["input"]) => transport("getUser", input),
  ping: () => transport("ping", {}),
});

export type Client = ReturnType<typeof createClient>;"""

macro signature(src: static string) =
  discard rpcSignature(parseStmt(src)[0])

static: doAssert compiles(signature("proc f(a: int): int = a"))
static: doAssert not compiles(signature("proc f[T](a: T): T = a"))
static: doAssert not compiles(signature("proc f(a = 1): int = a"))
static: doAssert not compiles(signature("proc f(a: var int) = discard"))
static: doAssert not compiles(signature("proc f(a: int): int"))
static: doAssert not compiles(signature("proc f(a {.context.}, b {.context.}: int) = discard"))
static: doAssert not compiles(signature("func f(a: int): int = a"))

# Renamed types: references use the TypeScript name, whatever their spelling.
const renamed = Known(names: {"Record": "DbRecord", "Page": "Paged"}.toTable)

static:
  doAssert toTsType(parseExpr("seq[Record]"), renamed) == "DbRecord[]"
  doAssert toTsType(parseExpr("Page[Record]"), renamed) == "Paged<DbRecord>"
  doAssert toTsDecl(parseStmt("type Record* = object\n  id: int")[0][0], renamed) ==
    "export type DbRecord = {\n  id: number;\n};"
  doAssert procedureToTs(rpcSignature(parseStmt(
    "proc get(id: int): Record = discard")[0]), renamed) ==
    "get: { input: { id: number }; output: DbRecord };"
