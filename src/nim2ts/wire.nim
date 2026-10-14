## JSON for the types nim2ts maps to TypeScript, so the wire matches the
## generated declarations in both directions.
##
## `toJson` writes exactly what the declarations promise. `fromJson` is
## strict: it rejects anything the TypeScript type would not allow and
## anything that does not fit the Nim type (out of range, wrong length).

import std/[json, macros, math, options, strutils, tables, typetraits]

template omitNone*() {.pragma.}
  ## Field pragma for `Option[T]`: `none` leaves the key out instead of
  ## writing `null`, and TypeScript gets `field?: T`.

type WireError* = object of ValueError
  path*: string ## where in the document, as `$.items[2].name`

const maxSafeInteger = 9007199254740991'i64
  ## `Number.MAX_SAFE_INTEGER`: TypeScript's `number` holds integers exactly
  ## up to here, so values beyond it are refused in both directions.

proc unsafeInteger(value: string): string =
  value & " exceeds JavaScript's safe integer range (±" & $maxSafeInteger & ")"

proc fail(path, msg: string) {.noreturn.} =
  var e = newException(WireError, "nim2ts: " & msg & " at " & path)
  e.path = path
  raise e

proc describe(n: JsonNode): string =
  if n.isNil:
    return "nothing"
  case n.kind
  of JNull: "null"
  of JBool: "a bool"
  of JInt: "an integer"
  of JFloat: "a float"
  of JString: "a string"
  of JObject: "an object"
  of JArray: "an array"

proc expect(n: JsonNode, kinds: set[JsonNodeKind], what, path: string) =
  if n.isNil or n.kind notin kinds:
    fail(path, "expected " & what & ", got " & describe(n))

# Writing

proc toJson*(x: string): JsonNode = newJString(x)
proc toJson*(x: char): JsonNode = newJString($x)
proc toJson*(x: bool): JsonNode = newJBool(x)
proc toJson*(x: SomeInteger): JsonNode =
  when sizeof(x) >= 8:
    let unsafe =
      when x is SomeUnsignedInt: x > uint64(maxSafeInteger)
      else: x > maxSafeInteger or x < -maxSafeInteger
    if unsafe:
      raise newException(WireError, "nim2ts: " & unsafeInteger($x))
  newJInt(BiggestInt(x))

proc toJson*(x: SomeFloat): JsonNode =
  if classify(x) in {fcNan, fcInf, fcNegInf}:
    raise newException(WireError, "nim2ts: " & $x & " has no JSON form")
  newJFloat(float(x))
proc toJson*(x: enum): JsonNode = newJString($x)

proc toJson*(x: JsonNode): JsonNode =
  if x.isNil: newJNull() else: x

proc toJson*[T](x: Option[T]): JsonNode =
  mixin toJson
  if x.isSome: toJson(x.get) else: newJNull()

proc toJson*[T](x: openArray[T]): JsonNode =
  mixin toJson
  result = newJArray()
  for item in x:
    result.add toJson(item)

proc toJson*[V](x: Table[string, V] | OrderedTable[string, V]): JsonNode =
  mixin toJson
  result = newJObject()
  for k, v in x:
    result[k] = toJson(v)

proc toJson*[T: distinct](x: T): JsonNode =
  mixin toJson
  toJson(distinctBase(x))

proc toJson*[T: object](x: T): JsonNode =
  ## A case object only has the fields of its active branch.
  mixin toJson
  result = newJObject()
  for k, v in fieldPairs(x):
    when v.hasCustomPragma(omitNone):
      when v isnot Option:
        {.error: "nim2ts: {.omitNone.} needs an Option field: " & k.}
      if v.isSome:
        result[k] = toJson(v.get)
    else:
      result[k] = toJson(v)

proc toJson*[T: ref](x: T): JsonNode =
  ## The TypeScript type has no `null` for a ref, so `nil` is refused;
  ## use `Option` for a value that may be missing.
  mixin toJson
  if x.isNil:
    raise newException(WireError, "nim2ts: cannot write a nil " & $T)
  toJson(x[])

# Reading. The generic readers are declared up front so they find each
# other whatever the nesting: they are private, so `mixin` cannot reach
# them from the caller's scope.

proc readJson[T](dst: var Option[T], n: JsonNode, path: string)
proc readJson[T](dst: var seq[T], n: JsonNode, path: string)
proc readJson[I, T](dst: var array[I, T], n: JsonNode, path: string)
proc readJson[V](
  dst: var (Table[string, V] | OrderedTable[string, V]), n: JsonNode, path: string
)
proc readJson[T: distinct](dst: var T, n: JsonNode, path: string)
proc readJson[T: object](dst: var T, n: JsonNode, path: string)
proc readJson[T: ref](dst: var T, n: JsonNode, path: string)

proc readJson(dst: var string, n: JsonNode, path: string) =
  expect(n, {JString}, "a string", path)
  dst = n.str

proc readJson(dst: var char, n: JsonNode, path: string) =
  expect(n, {JString}, "a string", path)
  if n.str.len != 1:
    fail(path, "expected a single character, got " & escapeJson(n.str))
  dst = n.str[0]

proc readJson(dst: var bool, n: JsonNode, path: string) =
  expect(n, {JBool}, "a bool", path)
  dst = n.bval

proc readJson[T: SomeInteger](dst: var T, n: JsonNode, path: string) =
  # std/json keeps an integer too large for int64 as a string of digits.
  if not n.isNil and n.kind == JString and n.str.len >= 19 and
      n.str.strip(trailing = false, chars = {'-'}).allCharsInSet(Digits):
    fail(path, unsafeInteger(n.str))
  expect(n, {JInt}, "an integer", path)
  let v = n.num
  if v > maxSafeInteger or v < -maxSafeInteger:
    fail(path, unsafeInteger($v))
  when T is SomeUnsignedInt and sizeof(T) >= sizeof(BiggestInt):
    if v < 0:
      fail(path, $v & " is out of range for " & $T)
  else:
    if v < BiggestInt(low(T)) or v > BiggestInt(high(T)):
      fail(path, $v & " is out of range for " & $T)
  dst = T(v)

proc readJson[T: SomeFloat](dst: var T, n: JsonNode, path: string) =
  expect(n, {JInt, JFloat}, "a number", path)
  dst = T(n.getFloat)

proc readJson[T: enum](dst: var T, n: JsonNode, path: string) =
  expect(n, {JString}, "a string", path)
  for e in T:
    if $e == n.str:
      dst = e
      return
  fail(path, escapeJson(n.str) & " is not a " & $T)

proc readJson(dst: var JsonNode, n: JsonNode, path: string) =
  dst = if n.isNil: newJNull() else: n

proc readJson[T](dst: var Option[T], n: JsonNode, path: string) =
  ## A missing key and `null` both read as `none`.
  mixin readJson
  if n.isNil or n.kind == JNull:
    dst = none(T)
  else:
    var v: T
    readJson(v, n, path)
    dst = some(v)

proc readJson[T](dst: var seq[T], n: JsonNode, path: string) =
  mixin readJson
  expect(n, {JArray}, "an array", path)
  dst.setLen(n.len)
  for i in 0 ..< n.len:
    readJson(dst[i], n[i], path & "[" & $i & "]")

proc readJson[I, T](dst: var array[I, T], n: JsonNode, path: string) =
  mixin readJson
  expect(n, {JArray}, "an array", path)
  if n.len != dst.len:
    fail(path, "expected " & $dst.len & " items, got " & $n.len)
  var i = 0
  for item in dst.mitems:
    readJson(item, n[i], path & "[" & $i & "]")
    inc i

proc readJson[V](
    dst: var (Table[string, V] | OrderedTable[string, V]), n: JsonNode, path: string
) =
  mixin readJson
  expect(n, {JObject}, "an object", path)
  for k, item in n.fields:
    var v: V
    readJson(v, item, path & "[" & escapeJson(k) & "]")
    dst[k] = v

proc readJson[T: distinct](dst: var T, n: JsonNode, path: string) =
  mixin readJson
  var base: distinctBase(T)
  readJson(base, n, path)
  dst = T(base)

proc readJson[T: object](dst: var T, n: JsonNode, path: string) =
  ## `fieldPairs` yields a discriminator before its branch, so setting it
  ## first selects the branch whose fields follow. Unknown keys are ignored.
  mixin readJson
  expect(n, {JObject}, "an object", path)
  for k, v in fieldPairs(dst):
    let item = n.getOrDefault(k)
    when v isnot Option:
      if item.isNil:
        fail(path & "." & k, "missing key")
    var value: typeof(v)
    readJson(value, item, path & "." & k)
    {.cast(uncheckedAssign).}:
      v = value

proc readJson[T: ref](dst: var T, n: JsonNode, path: string) =
  mixin readJson
  new(dst)
  readJson(dst[], n, path)

proc fromJson*[T](n: JsonNode, _: typedesc[T]): T =
  ## Raises `WireError` naming the first offending path.
  mixin readJson
  readJson(result, n, "$")
