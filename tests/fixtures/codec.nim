# Generic wrappers over toJson and fromJson, for a caller that imports
# neither nim2ts nor the modules of the types it passes.

import std/[json, options, tables]
import nim2ts

type
  Item* = object
    name*: string

  Node* = ref object
    item*: Item

  Wrapped* = distinct Item

  Kind* = enum
    plain, tagged

  Everything* = object
    items*: seq[Item]
    maybe*: Option[Item]
    byName*: Table[string, Item]
    ordered*: OrderedTable[string, Item]
    pair*: array[2, Item]
    nodes*: seq[Node]
    wrapped*: seq[Wrapped]
    case kind*: Kind
    of plain:
      discard
    of tagged:
      tags*: seq[Option[Item]]

proc sample*(): Everything =
  let item = Item(name: "a")
  Everything(
    items: @[item],
    maybe: some(item),
    byName: {"b": item}.toTable,
    ordered: {"c": item}.toOrderedTable,
    pair: [item, item],
    nodes: @[Node(item: item)],
    wrapped: @[Wrapped(item)],
    kind: tagged,
    tags: @[some(item), none(Item)],
  )

proc item*(): Item =
  Item(name: "a")

proc someItem*(): auto =
  some(item())

proc encode*[T](value: T): string =
  $toJson(value)

proc decode*[T](text: string, _: typedesc[T]): T =
  fromJson(parseJson(text), T)
