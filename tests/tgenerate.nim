# End-to-end test: compiling this file writes tests/generated.ts
# (see tests/config.nims), which must match the tests/expected.ts snapshot.
# The hand-written files in tests/json/ are values of those types, which
# toJson must write and fromJson read; those in tests/rpc/ are calls, which
# dispatch must answer. Each is written from the TypeScript type it names.

import std/[algorithm, json, options, os, strutils, tables, unittest]
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

  # Feature combinations: each type below crosses features that the types
  # above cover on their own.

  Result*[T] {.ts.} = object # generic × case object × bool discriminator
    case ok*: bool
    of true:
      value*: T
    of false:
      error*: string

  Level* {.ts: "Severity".} = enum # renamed enum with a custom wire value
    info, critical = "CRITICAL"

  Alert* {.ts.} = object # renamed discriminator × omitNone and distinct in a branch
    message*: string
    case level*: Level
    of info:
      discard
    of critical:
      pager* {.omitNone.}: Option[string]
      escalatedBy*: UserId

  Box*[Record] {.ts.} = object # a generic parameter named like a renamed type
    item*: Record

  Paged*[T] {.ts: "PageOf".} = object # renamed generic × omitNone of a parameter
    items*: seq[T]
    next* {.omitNone.}: Option[T]

  Named* {.ts: "HasName".} = ref object of RootObj # renamed base
    name*: string

  Pet* {.ts.} = ref object of Named # child of a renamed base × table of a renamed type
    species*: string
    records*: Table[string, Record]

  Versioned*[T] {.ts.} = object of RootObj # generic base × omitNone
    version*: int
    data*: T
    comment* {.omitNone.}: Option[T]

  Note* {.ts.} = object of Versioned[string] # child of a generic base's instance
    title*: string

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

proc nextPage*(page: Paged[Record]): Result[Paged[Record]] {.rpc.} =
  if page.next.isNone:
    Result[Paged[Record]](ok: false, error: "last page")
  else:
    Result[Paged[Record]](ok: true, value: Paged[Record](items: @[page.next.get]))

let testDir = currentSourcePath.parentDir

test "generated file matches snapshot":
  check readFile(testDir / "generated.ts") == readFile(testDir / "expected.ts")

let dir = Directory(users: @[
  User(id: UserId(1), name: "ann", email: "a@x", roles: @[admin], status: active),
  User(id: UserId(2), name: "bob", email: "b@x", roles: @[member], status: banned),
])

var expectedFiles: seq[string]
  ## Every JSON file a case below names. Declaring a case adds to it outside
  ## any test, so the completeness test holds even when run on its own.

template wire(name: string, value: untyped) =
  ## `tests/json/<name>.json` is what `toJson` writes for `value` and what
  ## `fromJson` reads back.
  expectedFiles.add "json" / name & ".json"
  test "json/" & name & ".json":
    let json = parseFile(testDir / "json" / name & ".json")
    check toJson(value) == json
    check toJson(fromJson(json, typeof(value))) == json

template call(name: string) =
  ## `tests/rpc/<name>.input.json` is a call of the procedure the name
  ## starts with, and `<name>.output.json` its answer.
  expectedFiles.add "rpc" / name & ".input.json"
  expectedFiles.add "rpc" / name & ".output.json"
  test "rpc/" & name:
    let input = parseFile(testDir / "rpc" / name & ".input.json")
    check dispatch(name.split('.')[0], input, dir) ==
      parseFile(testDir / "rpc" / name & ".output.json")

let ann = dir.users[0]

wire("User", ann)
wire("User.bio", User(id: UserId(3), name: "cy", email: "c@x", bio: some("hi"),
  scores: {"s": 0.5}.toTable, history: @[some(1), none(int)]))
wire("UserPage", UserPage(items: dir.users, total: 2))
wire("Shape.circle", Shape(name: "c", kind: circle, radius: 1))
wire("Shape.rect", Shape(name: "r", kind: rect, width: 2, height: 3))
wire("Shape.dot", Shape(name: "d", kind: dot))
wire("Label.circle", Label(kind: circle, radius: 1, text: "t"))
wire("Label.dot", Label(kind: dot, text: "t"))
wire("Owner", Owner(records: @[Record(id: 1), Record(id: 2)]))
wire("Result.ok", Result[int](ok: true, value: 1))
wire("Result.error", Result[int](ok: false, error: "e"))
wire("Alert.info", Alert(message: "m", level: info))
wire("Alert.critical", Alert(message: "m", level: critical, escalatedBy: UserId(1)))
wire("Alert.critical-paged", Alert(message: "m", level: critical, pager: some("p"),
  escalatedBy: UserId(1)))
wire("Box", Box[User](item: ann))
wire("PageOf.next", Paged[Record](items: @[Record(id: 1)], next: some(Record(id: 2))))
wire("PageOf.last", Paged[Record](items: @[]))
wire("Pet", Pet(name: "rex", species: "dog", records: {"vet": Record(id: 3)}.toTable))
wire("Note", Note(version: 2, data: "d", title: "t"))
wire("Note.commented", Note(version: 2, data: "d", comment: some("c"), title: "t"))

call("findUser")
call("listUsers.all")
call("listUsers.admin")
call("area")
call("ping")
call("firstRecord")
call("nextPage.more")
call("nextPage.last")

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

test "every expected JSON file is checked":
  var files: seq[string]
  for kind in ["json", "rpc"]:
    for file in walkFiles(testDir / kind / "*.json"):
      files.add kind / file.extractFilename
  check files.sorted == expectedFiles.sorted
