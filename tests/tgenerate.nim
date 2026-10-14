# End-to-end test: compiling this file writes tests/generated.ts
# (see tests/config.nims), which must match the tests/expected.ts snapshot.

import std/[json, options, os, sequtils, tables, unittest]
import nim2ts

type
  Role* {.ts.} = enum
    admin, member

  Status* {.ts.} = enum
    active = "ACTIVE"
    banned = "BANNED"

  UserId* {.ts.} = distinct int

  Tags* {.ts.} = seq[string]

  Entity* {.ts.} = ref object of RootObj
    id*: UserId

  User* {.ts.} = ref object of Entity
    name*, email*: string
    nickname*: Option[string]
    bio* {.omitNone.}: Option[string]
    roles*: seq[Role]
    status*: Status
    tags*: Tags
    `type`*: string
    scores*: Table[string, float]
    history*: seq[Option[int]]

  Page*[T] {.ts.} = object
    items*: seq[T]
    total*: Natural

  UserPage* {.ts.} = Page[User]

  ShapeKind* {.ts.} = enum
    circle, rect = "RECT", dot

  Shape* {.ts.} = object
    name*: string
    case kind*: ShapeKind
    of circle:
      radius*: float
    of rect:
      width*, height*: float
    else:
      discard

  LabeledShape* {.ts.} = ref object of RootObj
    case kind*: ShapeKind
    of circle:
      radius*: float
    else:
      discard

  Label* {.ts.} = ref object of LabeledShape
    text*: string

  Owner* {.ts.} = object
    records*: seq[Record]

  Record* {.ts: "DbRecord".} = object
    id*: int

type
  Directory = ref object
    users: seq[User]

  NotFound = object of CatchableError

proc findUser*(dir {.context.}: Directory, id: UserId): User {.rpc.} =
  for u in dir.users:
    if u.id.int == id.int:
      return u
  raise newException(NotFound, "no user " & $id.int)

proc listUsers*(dir {.context.}: Directory, role: Option[Role]): UserPage {.rpc.} =
  for u in dir.users:
    if role.isNone or role.get in u.roles:
      result.items.add u
  result.total = result.items.len

proc area*(shape: Shape): float {.rpc.} =
  case shape.kind
  of circle: 3.0 * shape.radius * shape.radius
  of rect: shape.width * shape.height
  of dot: 0

proc ping*() {.rpc.} =
  discard

proc firstRecord*(owner: Owner): Record {.rpc.} =
  owner.records[0]

test "generated file matches snapshot":
  let dir = currentSourcePath.parentDir
  check readFile(dir / "generated.ts") == readFile(dir / "expected.ts")

test "toJson writes the keys of the matching union member":
  proc keys(s: Shape): seq[string] = toSeq(toJson(s).keys)
  check keys(Shape(name: "c", kind: circle)) == @["name", "kind", "radius"]
  check keys(Shape(name: "r", kind: rect)) == @["name", "kind", "width", "height"]
  check keys(Shape(name: "d", kind: dot)) == @["name", "kind"]
  check toJson(Shape(kind: rect))["kind"].getStr == "RECT"

test "a child of a case object writes its parent's branch":
  check toSeq(toJson(Label(kind: circle, radius: 1, text: "t")).keys) ==
    @["text", "kind", "radius"]

test "round trip through the generated types":
  let user = User(id: UserId(1), name: "n", email: "e", roles: @[admin],
    status: banned, tags: @["t"], scores: {"s": 1.0}.toTable,
    history: @[some(1), none(int)])
  let page = UserPage(items: @[user], total: 1)
  check toJson(fromJson(toJson(page), UserPage)) == toJson(page)
  check "bio" notin toJson(user)

let dir = Directory(users: @[
  User(id: UserId(1), name: "ann", email: "a@x", roles: @[admin], status: active),
  User(id: UserId(2), name: "bob", email: "b@x", roles: @[member], status: banned),
])

test "dispatch reads parameters, passes the context and writes the result":
  check dispatch("findUser", %*{"id": 2}, dir)["name"].getStr == "bob"
  check dispatch("listUsers", %*{"role": "admin"}, dir)["total"].getInt == 1
  check dispatch("listUsers", %*{}, dir)["total"].getInt == 2
  check dispatch("area", %*{"shape": {"name": "r", "kind": "RECT", "width": 2, "height": 3}}, dir).getFloat == 6
  check dispatch("ping", %*{}, dir).kind == JNull
  check dispatch("firstRecord", %*{"owner": {"records": [{"id": 4}]}}, dir) == %*{"id": 4}

test "dispatch rejects unknown procedures and invalid input":
  expect UnknownProcedure:
    discard dispatch("dropUsers", %*{}, dir)
  try:
    discard dispatch("findUser", %*{"id": "2"}, dir)
    fail()
  except WireError as e:
    check e.path == "$.id"

test "errors raised by a procedure pass through":
  expect NotFound:
    discard dispatch("findUser", %*{"id": 3}, dir)

test "dispatch needs a context when a procedure takes one":
  check not compiles(dispatch("ping", %*{}))
