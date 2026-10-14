# Strict JSON in both directions. No `{.ts.}` here: that would rewrite
# tests/generated.ts, which tgenerate owns.

import std/[json, options, tables, unittest]
import nim2ts/wire

type
  Kind = enum
    circle, rect = "RECT", dot

  Id = distinct int

  Base = ref object of RootObj
    id: Id

  Item = ref object of Base
    name: string
    initial: char
    count: Natural
    small: uint8
    ratio: float
    pair: array[2, int]
    tags: seq[string]
    scores: OrderedTable[string, float]
    extra: JsonNode
    nick: Option[string]
    bio {.omitNone.}: Option[string]
    case kind: Kind
    of circle:
      radius: float
    of rect:
      width, height: float
    else:
      discard

proc sample(): Item =
  Item(id: Id(7), name: "a", initial: 'x', count: 3, small: 255, ratio: 0.5,
    pair: [1, 2], tags: @["t"], scores: {"s": 1.0}.toOrderedTable,
    extra: %*{"any": [1]}, kind: rect, width: 2, height: 3)

proc rejects(json: string, path: string): bool =
  try:
    discard fromJson(parseJson(json), Item)
  except WireError as e:
    if e.path == path:
      return true
    echo "  rejected at ", e.path, ": ", e.msg

proc withKey(key: string, value: JsonNode): string =
  let j = toJson(sample())
  j[key] = value
  $j

proc withoutKey(key: string): string =
  let j = toJson(sample())
  j.delete(key)
  $j

test "writes the fields of the active branch":
  let j = toJson(sample())
  check j["kind"].getStr == "RECT"
  check j["width"].getFloat == 2
  check "radius" notin j
  check j["id"].getInt == 7
  check j["initial"].getStr == "x"

test "omitNone leaves the key out, a plain Option writes null":
  let j = toJson(sample())
  check j["nick"].kind == JNull
  check "bio" notin j
  var item = sample()
  item.bio = some("hi")
  check toJson(item)["bio"].getStr == "hi"

test "round trip":
  let j = toJson(sample())
  check toJson(fromJson(j, Item)) == j

test "missing and null Options read as none":
  check fromJson(parseJson(withoutKey("nick")), Item).nick.isNone
  check fromJson(parseJson(withKey("bio", newJNull())), Item).bio.isNone

test "refuses to write a nil ref":
  expect WireError:
    discard toJson(Item(nil))

test "rejects what the types do not allow":
  check rejects(withoutKey("name"), "$.name")
  check rejects(withoutKey("height"), "$.height")
  check rejects(withKey("name", %1), "$.name")
  check rejects(withKey("count", %(-1)), "$.count")
  check rejects(withKey("small", %256), "$.small")
  check rejects(withKey("id", %1.5), "$.id")
  check rejects(withKey("initial", %"xy"), "$.initial")
  check rejects(withKey("kind", %"rect"), "$.kind")
  check rejects(withKey("pair", %[1]), "$.pair")
  check rejects(withKey("tags", %[1]), "$.tags[0]")
  check rejects(withKey("scores", %*{"s": "x"}), "$.scores[\"s\"]")
  check rejects("null", "$")

test "reads the branch the discriminator selects":
  let j = toJson(sample())
  j["kind"] = %"circle"
  j["radius"] = %4
  let item = fromJson(j, Item)
  check item.kind == circle
  check item.radius == 4
  j.delete("radius")
  check rejects($j, "$.radius")
