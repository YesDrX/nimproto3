## Test wire_format module
import nimproto3

when isMainModule:
  echo "Testing varint encoding/decoding..."

  # Test varint
  let encoded150 = encodeVarint(150)
  echo "Encoded 150: ", encoded150
  var pos = 0
  let decoded150 = decodeVarint(encoded150, pos)
  echo "Decoded: ", decoded150
  assert decoded150 == 150

  # Test zigzag
  let zigzag = encodeZigZag(-1)
  echo "\nZigZag encode(-1): ", zigzag
  let unzigzag = decodeZigZag(zigzag)
  echo "ZigZag decode: ", unzigzag
  assert unzigzag == -1

  # Test field key
  let fieldKey = encodeFieldKey(1, wtLengthDelimited)
  echo "\nField key (field=1, type=length-delimited): ", fieldKey
  pos = 0
  let (fieldNum, wireType) = decodeFieldKey(fieldKey, pos)
  echo "Decoded field number: ", fieldNum, ", wire type: ", wireType
  assert fieldNum == 1

  # Test string encoding
  let encodedStr = encodeString("hello")
  echo "\nEncoded 'hello': ", encodedStr
  pos = 0
  let decodedStr = decodeString(encodedStr, pos)
  echo "Decoded: ", decodedStr
  assert decodedStr == "hello"

  echo "\n✅ All wire format tests passed!"
