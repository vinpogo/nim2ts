# End-to-end test: compiling this file writes tests/generated.ts
# (see tests/config.nims), which must match the tests/expected.ts snapshot.

import std/[options, os, tables, unittest]
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

test "generated file matches snapshot":
  let dir = currentSourcePath.parentDir
  check readFile(dir / "generated.ts") == readFile(dir / "expected.ts")
