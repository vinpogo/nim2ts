import std/json
from nim2ts import dispatch
from endpoints import getUser

for (procedure, input) in [("getUser", %*{"id": 7}), ("foo", %*{}), ("Foo", %*{}), ("hidden", %*{})]:
  echo dispatch(procedure, input)
