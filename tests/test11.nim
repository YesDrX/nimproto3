import unittest
import nimproto3

proto3 """
syntax = "proto3";
message Simple {
  string name = 1;
  int32 id = 2;
}
"""

proto3 """
syntax = "proto3";
message WithMap {
  map<string, int32> scores = 1;
  string name = 2;
}
"""

suite "Unknown field skipping (forward compatibility)":
  test "skipField handles every wire type":
    # varint
    block:
      var buf = encodeVarint(300'u64)
      var pos = 0
      skipField(buf, pos, wtVarint)
      check pos == buf.len
    # 32-bit
    block:
      var buf: seq[byte] = @[1'u8, 2'u8, 3'u8, 4'u8]
      var pos = 0
      skipField(buf, pos, wt32Bit)
      check pos == 4
    # 64-bit
    block:
      var buf: seq[byte] = @[1'u8, 2'u8, 3'u8, 4'u8, 5'u8, 6'u8, 7'u8, 8'u8]
      var pos = 0
      skipField(buf, pos, wt64Bit)
      check pos == 8
    # length-delimited
    block:
      var buf = encodeString("hello")
      var pos = 0
      skipField(buf, pos, wtLengthDelimited)
      check pos == buf.len
    # group (deprecated but legal): skip to matching end group
    block:
      var buf: seq[byte] = @[]
      buf.add(encodeFieldKey(1, wtVarint))
      buf.add(encodeVarint(42'u64))
      buf.add(encodeFieldKey(2, wtLengthDelimited))
      buf.add(encodeString("x"))
      buf.add(encodeFieldKey(1, wtEndGroup))
      var pos = 0
      skipField(buf, pos, wtStartGroup)
      check pos == buf.len

  test "unknown varint value 7 in the middle no longer raises wiretype 7":
    var wire: seq[byte] = @[]
    wire.add(encodeFieldKey(1, wtLengthDelimited))
    wire.add(encodeString("alice"))
    wire.add(encodeFieldKey(5, wtVarint)) # server-only field
    wire.add(encodeVarint(7'u64))         # low 3 bits = 7: old code read this as a tag
    wire.add(encodeFieldKey(2, wtVarint))
    wire.add(encodeInt32(42'i32))
    let back = Simple.fromBinary(wire)
    check back.name == "alice"
    check back.id == 42

  test "unknown varint value 6 in the middle no longer raises wiretype 6":
    var wire: seq[byte] = @[]
    wire.add(encodeFieldKey(1, wtLengthDelimited))
    wire.add(encodeString("alice"))
    wire.add(encodeFieldKey(5, wtVarint))
    wire.add(encodeVarint(6'u64))
    wire.add(encodeFieldKey(2, wtVarint))
    wire.add(encodeInt32(99'i32))
    let back = Simple.fromBinary(wire)
    check back.name == "alice"
    check back.id == 99

  test "unknown length-delimited, fixed32 and fixed64 fields are skipped":
    var wire: seq[byte] = @[]
    wire.add(encodeFieldKey(1, wtLengthDelimited))
    wire.add(encodeString("alice"))
    wire.add(encodeFieldKey(6, wtLengthDelimited))
    wire.add(encodeString("extra"))
    wire.add(encodeFieldKey(7, wt32Bit))
    wire.add(@[1'u8, 2'u8, 3'u8, 4'u8])
    wire.add(encodeFieldKey(8, wt64Bit))
    wire.add(@[1'u8, 2'u8, 3'u8, 4'u8, 5'u8, 6'u8, 7'u8, 8'u8])
    wire.add(encodeFieldKey(2, wtVarint))
    wire.add(encodeInt32(42'i32))
    let back = Simple.fromBinary(wire)
    check back.name == "alice"
    check back.id == 42

  test "large message reproduces invalid wiretype 7 at offset 660":
    var bigName = newString(655)
    for i in 0 ..< bigName.len:
      bigName[i] = 'A'
    var wire: seq[byte] = @[]
    wire.add(encodeFieldKey(1, wtLengthDelimited))
    wire.add(encodeString(bigName))
    wire.add(encodeFieldKey(5, wtVarint))
    wire.add(encodeVarint(7'u64))
    wire.add(encodeFieldKey(2, wtVarint))
    wire.add(encodeInt32(42'i32))
    let back = Simple.fromBinary(wire)
    check back.name == bigName
    check back.id == 42

  test "toJson on binary with unknown fields keeps known fields":
    var wire: seq[byte] = @[]
    wire.add(encodeFieldKey(1, wtLengthDelimited))
    wire.add(encodeString("alice"))
    wire.add(encodeFieldKey(5, wtVarint))
    wire.add(encodeVarint(7'u64))
    wire.add(encodeFieldKey(2, wtVarint))
    wire.add(encodeInt32(42'i32))
    let node = Simple.toJson(wire)
    check node["name"].getStr == "alice"
    check node["id"].getInt == 42

  test "map entry with unknown inner field still decodes":
    var entry: seq[byte] = @[]
    entry.add(encodeFieldKey(1, wtLengthDelimited))
    entry.add(encodeString("math"))
    entry.add(encodeFieldKey(2, wtVarint))
    entry.add(encodeInt32(95'i32))
    entry.add(encodeFieldKey(3, wtVarint)) # unknown inside the map entry
    entry.add(encodeVarint(7'u64))
    var wire: seq[byte] = @[]
    wire.add(encodeFieldKey(1, wtLengthDelimited))
    wire.add(encodeLengthDelimited(entry))
    wire.add(encodeFieldKey(2, wtLengthDelimited))
    wire.add(encodeString("alice"))
    let back = WithMap.fromBinary(wire)
    check back.scores["math"] == 95
    check back.name == "alice"

  test "roundtrip without unknown fields still works":
    let m = Simple(name: "bob", id: -1'i32)
    let back = Simple.fromBinary(m.toBinary())
    check back == m
