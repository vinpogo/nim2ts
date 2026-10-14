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

test "generated file matches snapshot":
  let dir = currentSourcePath.parentDir
  check readFile(dir / "generated.ts") == readFile(dir / "expected.ts")

test "toJson writes the keys of the matching union member":
  proc keys(s: Shape): seq[string] = toSeq(toJson(s).keys)
  check keys(Shape(name: "c", kind: circle)) == @["name", "kind", "radius"]
  check keys(Shape(name: "r", kind: rect)) == @["name", "kind", "width", "height"]
  check keys(Shape(name: "d", kind: dot)) == @["name", "kind"]
  check toJson(Shape(kind: rect))["kind"].getStr == "RECT"

test "round trip through the generated types":
  let user = User(id: UserId(1), name: "n", email: "e", roles: @[admin],
    status: banned, tags: @["t"], scores: {"s": 1.0}.toTable,
    history: @[some(1), none(int)])
  let page = UserPage(items: @[user], total: 1)
  check toJson(fromJson(toJson(page), UserPage)) == toJson(page)
  check "bio" notin toJson(user)
