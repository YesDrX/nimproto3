import std/[strutils]

# ============================================================================
# RFC 7541 Appendix B: Huffman Code Table
# ============================================================================

type
  HuffmanSymbol = object
    code: uint32
    len: int

const
  # EOS Symbol: 30 bits of '1's -> 0x3fffffff
  EOS_SYM = 256

  HuffmanTable: array[257, HuffmanSymbol] = [
    HuffmanSymbol(code: 0x1ff8, len: 13),       # 0
    HuffmanSymbol(code: 0x7fffd8, len: 23),     # 1
    HuffmanSymbol(code: 0xfffffe2, len: 28),    # 2
    HuffmanSymbol(code: 0xfffffe3, len: 28),    # 3
    HuffmanSymbol(code: 0xfffffe4, len: 28),    # 4
    HuffmanSymbol(code: 0xfffffe5, len: 28),    # 5
    HuffmanSymbol(code: 0xfffffe6, len: 28),    # 6
    HuffmanSymbol(code: 0xfffffe7, len: 28),    # 7
    HuffmanSymbol(code: 0xfffffe8, len: 28),    # 8
    HuffmanSymbol(code: 0xffffea, len: 24),     # 9
    HuffmanSymbol(code: 0x3ffffffc, len: 30),   # 10
    HuffmanSymbol(code: 0xfffffe9, len: 28),    # 11
    HuffmanSymbol(code: 0xfffffea, len: 28),    # 12
    HuffmanSymbol(code: 0x3ffffffd, len: 30),   # 13
    HuffmanSymbol(code: 0xfffffeb, len: 28),    # 14
    HuffmanSymbol(code: 0xfffffec, len: 28),    # 15
    HuffmanSymbol(code: 0xfffffed, len: 28),    # 16
    HuffmanSymbol(code: 0xfffffee, len: 28),    # 17
    HuffmanSymbol(code: 0xfffffef, len: 28),    # 18
    HuffmanSymbol(code: 0xffffff0, len: 28),    # 19
    HuffmanSymbol(code: 0xffffff1, len: 28),    # 20
    HuffmanSymbol(code: 0xffffff2, len: 28),    # 21
    HuffmanSymbol(code: 0x3ffffffe, len: 30),   # 22
    HuffmanSymbol(code: 0xffffff3, len: 28),    # 23
    HuffmanSymbol(code: 0xffffff4, len: 28),    # 24
    HuffmanSymbol(code: 0xffffff5, len: 28),    # 25
    HuffmanSymbol(code: 0xffffff6, len: 28),    # 26
    HuffmanSymbol(code: 0xffffff7, len: 28),    # 27
    HuffmanSymbol(code: 0xffffff8, len: 28),    # 28
    HuffmanSymbol(code: 0xffffff9, len: 28),    # 29
    HuffmanSymbol(code: 0xffffffa, len: 28),    # 30
    HuffmanSymbol(code: 0xffffffb, len: 28),    # 31
    HuffmanSymbol(code: 0x14, len: 6),          # 32 (space)
    HuffmanSymbol(code: 0x3f8, len: 10),        # 33 (!)
    HuffmanSymbol(code: 0x3f9, len: 10),        # 34 (")
    HuffmanSymbol(code: 0xffa, len: 12),        # 35 (#)
    HuffmanSymbol(code: 0x1ff9, len: 13),       # 36 ($)
    HuffmanSymbol(code: 0x15, len: 6),          # 37 (%)
    HuffmanSymbol(code: 0xf8, len: 8),          # 38 (&)
    HuffmanSymbol(code: 0x7fa, len: 11),        # 39 (')
    HuffmanSymbol(code: 0x3fa, len: 10),        # 40 (()
    HuffmanSymbol(code: 0x3fb, len: 10),        # 41 ())
    HuffmanSymbol(code: 0xf9, len: 8),          # 42 (*)
    HuffmanSymbol(code: 0x7fb, len: 11),        # 43 (+)
    HuffmanSymbol(code: 0xfa, len: 8),          # 44 (,)
    HuffmanSymbol(code: 0x16, len: 6),          # 45 (-)
    HuffmanSymbol(code: 0x17, len: 6),          # 46 (.)
    HuffmanSymbol(code: 0x18, len: 6),          # 47 (/)
    HuffmanSymbol(code: 0x0, len: 5),           # 48 (0)
    HuffmanSymbol(code: 0x1, len: 5),           # 49 (1)
    HuffmanSymbol(code: 0x2, len: 5),           # 50 (2)
    HuffmanSymbol(code: 0x19, len: 6),          # 51 (3)
    HuffmanSymbol(code: 0x1a, len: 6),          # 52 (4)
    HuffmanSymbol(code: 0x1b, len: 6),          # 53 (5)
    HuffmanSymbol(code: 0x1c, len: 6),          # 54 (6)
    HuffmanSymbol(code: 0x1d, len: 6),          # 55 (7)
    HuffmanSymbol(code: 0x1e, len: 6),          # 56 (8)
    HuffmanSymbol(code: 0x1f, len: 6),          # 57 (9)
    HuffmanSymbol(code: 0x5c, len: 7),          # 58 (:)
    HuffmanSymbol(code: 0xfb, len: 8),          # 59 (;)
    HuffmanSymbol(code: 0x7ffc, len: 15),       # 60 (<)
    HuffmanSymbol(code: 0x20, len: 6),          # 61 (=)
    HuffmanSymbol(code: 0xffb, len: 12),        # 62 (>)
    HuffmanSymbol(code: 0x3fc, len: 10),        # 63 (?)
    HuffmanSymbol(code: 0x1ffa, len: 13),       # 64 (@)
    HuffmanSymbol(code: 0x21, len: 6),          # 65 (A)
    HuffmanSymbol(code: 0x5d, len: 7),          # 66 (B)
    HuffmanSymbol(code: 0x5e, len: 7),          # 67 (C)
    HuffmanSymbol(code: 0x5f, len: 7),          # 68 (D)
    HuffmanSymbol(code: 0x60, len: 7),          # 69 (E)
    HuffmanSymbol(code: 0x61, len: 7),          # 70 (F)
    HuffmanSymbol(code: 0x62, len: 7),          # 71 (G)
    HuffmanSymbol(code: 0x63, len: 7),          # 72 (H)
    HuffmanSymbol(code: 0x64, len: 7),          # 73 (I)
    HuffmanSymbol(code: 0x65, len: 7),          # 74 (J)
    HuffmanSymbol(code: 0x66, len: 7),          # 75 (K)
    HuffmanSymbol(code: 0x67, len: 7),          # 76 (L)
    HuffmanSymbol(code: 0x68, len: 7),          # 77 (M)
    HuffmanSymbol(code: 0x69, len: 7),          # 78 (N)
    HuffmanSymbol(code: 0x6a, len: 7),          # 79 (O)
    HuffmanSymbol(code: 0x6b, len: 7),          # 80 (P)
    HuffmanSymbol(code: 0x6c, len: 7),          # 81 (Q)
    HuffmanSymbol(code: 0x6d, len: 7),          # 82 (R)
    HuffmanSymbol(code: 0x6e, len: 7),          # 83 (S)
    HuffmanSymbol(code: 0x6f, len: 7),          # 84 (T)
    HuffmanSymbol(code: 0x70, len: 7),          # 85 (U)
    HuffmanSymbol(code: 0x71, len: 7),          # 86 (V)
    HuffmanSymbol(code: 0x72, len: 7),          # 87 (W)
    HuffmanSymbol(code: 0xfc, len: 8),          # 88 (X)
    HuffmanSymbol(code: 0x73, len: 7),          # 89 (Y)
    HuffmanSymbol(code: 0xfd, len: 8),          # 90 (Z)
    HuffmanSymbol(code: 0x1ffb, len: 13),       # 91 ([)
    HuffmanSymbol(code: 0x7fff0, len: 19),      # 92 (\)
    HuffmanSymbol(code: 0x1ffc, len: 13),       # 93 (])
    HuffmanSymbol(code: 0x3ffc, len: 14),       # 94 (^)
    HuffmanSymbol(code: 0x22, len: 6),          # 95 (_)
    HuffmanSymbol(code: 0x7ffd, len: 15),       # 96 (`)
    HuffmanSymbol(code: 0x3, len: 5),           # 97 (a)
    HuffmanSymbol(code: 0x23, len: 6),          # 98 (b)
    HuffmanSymbol(code: 0x4, len: 5),           # 99 (c)
    HuffmanSymbol(code: 0x24, len: 6),          # 100 (d)
    HuffmanSymbol(code: 0x5, len: 5),           # 101 (e)
    HuffmanSymbol(code: 0x25, len: 6),          # 102 (f)
    HuffmanSymbol(code: 0x26, len: 6),          # 103 (g)
    HuffmanSymbol(code: 0x27, len: 6),          # 104 (h)
    HuffmanSymbol(code: 0x6, len: 5),           # 105 (i)
    HuffmanSymbol(code: 0x74, len: 7),          # 106 (j)
    HuffmanSymbol(code: 0x75, len: 7),          # 107 (k)
    HuffmanSymbol(code: 0x28, len: 6),          # 108 (l)
    HuffmanSymbol(code: 0x29, len: 6),          # 109 (m)
    HuffmanSymbol(code: 0x2a, len: 6),          # 110 (n)
    HuffmanSymbol(code: 0x7, len: 5),           # 111 (o)
    HuffmanSymbol(code: 0x2b, len: 6),          # 112 (p)
    HuffmanSymbol(code: 0x76, len: 7),          # 113 (q)
    HuffmanSymbol(code: 0x2c, len: 6),          # 114 (r)
    HuffmanSymbol(code: 0x8, len: 5),           # 115 (s)
    HuffmanSymbol(code: 0x9, len: 5),           # 116 (t)
    HuffmanSymbol(code: 0x2d, len: 6),          # 117 (u)
    HuffmanSymbol(code: 0x77, len: 7),          # 118 (v)
    HuffmanSymbol(code: 0x78, len: 7),          # 119 (w)
    HuffmanSymbol(code: 0x79, len: 7),          # 120 (x)
    HuffmanSymbol(code: 0x7a, len: 7),          # 121 (y)
    HuffmanSymbol(code: 0x7b, len: 7),          # 122 (z)
    HuffmanSymbol(code: 0x7ffe, len: 15),       # 123 ({)
    HuffmanSymbol(code: 0x7fc, len: 11),        # 124 (|)
    HuffmanSymbol(code: 0x3ffd, len: 14),       # 125 (})
    HuffmanSymbol(code: 0x1ffd, len: 13),       # 126 (~)
    HuffmanSymbol(code: 0xffffffc, len: 28),    # 127
    HuffmanSymbol(code: 0xfffe6, len: 20),      # 128
    HuffmanSymbol(code: 0x3fffd2, len: 22),     # 129
    HuffmanSymbol(code: 0xfffe7, len: 20),      # 130
    HuffmanSymbol(code: 0xfffe8, len: 20),      # 131
    HuffmanSymbol(code: 0x3fffd3, len: 22),     # 132
    HuffmanSymbol(code: 0x3fffd4, len: 22),     # 133
    HuffmanSymbol(code: 0x3fffd5, len: 22),     # 134
    HuffmanSymbol(code: 0x7fffd9, len: 23),     # 135
    HuffmanSymbol(code: 0x3fffd6, len: 22),     # 136
    HuffmanSymbol(code: 0x7fffda, len: 23),     # 137
    HuffmanSymbol(code: 0x7fffdb, len: 23),     # 138
    HuffmanSymbol(code: 0x7fffdc, len: 23),     # 139
    HuffmanSymbol(code: 0x7fffdd, len: 23),     # 140
    HuffmanSymbol(code: 0x7fffde, len: 23),     # 141
    HuffmanSymbol(code: 0xffffeb, len: 24),     # 142
    HuffmanSymbol(code: 0x7fffdf, len: 23),     # 143
    HuffmanSymbol(code: 0xffffec, len: 24),     # 144
    HuffmanSymbol(code: 0xffffed, len: 24),     # 145
    HuffmanSymbol(code: 0x3fffd7, len: 22),     # 146
    HuffmanSymbol(code: 0x7fffe0, len: 23),     # 147
    HuffmanSymbol(code: 0xffffee, len: 24),     # 148
    HuffmanSymbol(code: 0x7fffe1, len: 23),     # 149
    HuffmanSymbol(code: 0x7fffe2, len: 23),     # 150
    HuffmanSymbol(code: 0x7fffe3, len: 23),     # 151
    HuffmanSymbol(code: 0x7fffe4, len: 23),     # 152
    HuffmanSymbol(code: 0x1fffdc, len: 21),     # 153
    HuffmanSymbol(code: 0x3fffd8, len: 22),     # 154
    HuffmanSymbol(code: 0x7fffe5, len: 23),     # 155
    HuffmanSymbol(code: 0x3fffd9, len: 22),     # 156
    HuffmanSymbol(code: 0x7fffe6, len: 23),     # 157
    HuffmanSymbol(code: 0x7fffe7, len: 23),     # 158
    HuffmanSymbol(code: 0xffffef, len: 24),     # 159
    HuffmanSymbol(code: 0x3fffda, len: 22),     # 160
    HuffmanSymbol(code: 0x1fffdd, len: 21),     # 161
    HuffmanSymbol(code: 0xfffe9, len: 20),      # 162
    HuffmanSymbol(code: 0x3fffdb, len: 22),     # 163
    HuffmanSymbol(code: 0x3fffdc, len: 22),     # 164
    HuffmanSymbol(code: 0x7fffe8, len: 23),     # 165
    HuffmanSymbol(code: 0x7fffe9, len: 23),     # 166
    HuffmanSymbol(code: 0x1fffde, len: 21),     # 167
    HuffmanSymbol(code: 0x7fffea, len: 23),     # 168
    HuffmanSymbol(code: 0x3fffdd, len: 22),     # 169
    HuffmanSymbol(code: 0x3fffde, len: 22),     # 170
    HuffmanSymbol(code: 0xfffff0, len: 24),     # 171
    HuffmanSymbol(code: 0x1fffdf, len: 21),     # 172
    HuffmanSymbol(code: 0x3fffdf, len: 22),     # 173
    HuffmanSymbol(code: 0x7fffeb, len: 23),     # 174
    HuffmanSymbol(code: 0x7fffec, len: 23),     # 175
    HuffmanSymbol(code: 0x1fffe0, len: 21),     # 176
    HuffmanSymbol(code: 0x1fffe1, len: 21),     # 177
    HuffmanSymbol(code: 0x3fffe0, len: 22),     # 178
    HuffmanSymbol(code: 0x1fffe2, len: 21),     # 179
    HuffmanSymbol(code: 0x7fffed, len: 23),     # 180
    HuffmanSymbol(code: 0x3fffe1, len: 22),     # 181
    HuffmanSymbol(code: 0x7fffee, len: 23),     # 182
    HuffmanSymbol(code: 0x7fffef, len: 23),     # 183
    HuffmanSymbol(code: 0xfffea, len: 20),      # 184
    HuffmanSymbol(code: 0x3fffe2, len: 22),     # 185
    HuffmanSymbol(code: 0x3fffe3, len: 22),     # 186
    HuffmanSymbol(code: 0x3fffe4, len: 22),     # 187
    HuffmanSymbol(code: 0x7ffff0, len: 23),     # 188
    HuffmanSymbol(code: 0x3fffe5, len: 22),     # 189
    HuffmanSymbol(code: 0x3fffe6, len: 22),     # 190
    HuffmanSymbol(code: 0x7ffff1, len: 23),     # 191
    HuffmanSymbol(code: 0x3ffffe0, len: 26),    # 192
    HuffmanSymbol(code: 0x3ffffe1, len: 26),    # 193
    HuffmanSymbol(code: 0xfffeb, len: 20),      # 194
    HuffmanSymbol(code: 0x7fff1, len: 19),      # 195
    HuffmanSymbol(code: 0x3fffe7, len: 22),     # 196
    HuffmanSymbol(code: 0x7ffff2, len: 23),     # 197
    HuffmanSymbol(code: 0x3fffe8, len: 22),     # 198
    HuffmanSymbol(code: 0x1ffffec, len: 25),    # 199
    HuffmanSymbol(code: 0x3ffffe2, len: 26),    # 200
    HuffmanSymbol(code: 0x3ffffe3, len: 26),    # 201
    HuffmanSymbol(code: 0x3ffffe4, len: 26),    # 202
    HuffmanSymbol(code: 0x7ffffde, len: 27),    # 203
    HuffmanSymbol(code: 0x7ffffdf, len: 27),    # 204
    HuffmanSymbol(code: 0x3ffffe5, len: 26),    # 205
    HuffmanSymbol(code: 0xfffff1, len: 24),     # 206
    HuffmanSymbol(code: 0x1ffffed, len: 25),    # 207
    HuffmanSymbol(code: 0x7fff2, len: 19),      # 208
    HuffmanSymbol(code: 0x1fffe3, len: 21),     # 209
    HuffmanSymbol(code: 0x3ffffe6, len: 26),    # 210
    HuffmanSymbol(code: 0x7ffffe0, len: 27),    # 211
    HuffmanSymbol(code: 0x7ffffe1, len: 27),    # 212
    HuffmanSymbol(code: 0x3ffffe7, len: 26),    # 213
    HuffmanSymbol(code: 0x7ffffe2, len: 27),    # 214
    HuffmanSymbol(code: 0xfffff2, len: 24),     # 215
    HuffmanSymbol(code: 0x1fffe4, len: 21),     # 216
    HuffmanSymbol(code: 0x1fffe5, len: 21),     # 217
    HuffmanSymbol(code: 0x3ffffe8, len: 26),    # 218
    HuffmanSymbol(code: 0x3ffffe9, len: 26),    # 219
    HuffmanSymbol(code: 0xffffffd, len: 28),    # 220
    HuffmanSymbol(code: 0x7ffffe3, len: 27),    # 221
    HuffmanSymbol(code: 0x7ffffe4, len: 27),    # 222
    HuffmanSymbol(code: 0x7ffffe5, len: 27),    # 223
    HuffmanSymbol(code: 0xfffec, len: 20),      # 224
    HuffmanSymbol(code: 0xfffff3, len: 24),     # 225
    HuffmanSymbol(code: 0xfffed, len: 20),      # 226
    HuffmanSymbol(code: 0x1fffe6, len: 21),     # 227
    HuffmanSymbol(code: 0x3fffe9, len: 22),     # 228
    HuffmanSymbol(code: 0x1fffe7, len: 21),     # 229
    HuffmanSymbol(code: 0x1fffe8, len: 21),     # 230
    HuffmanSymbol(code: 0x7ffff3, len: 23),     # 231
    HuffmanSymbol(code: 0x3fffea, len: 22),     # 232
    HuffmanSymbol(code: 0x3fffeb, len: 22),     # 233
    HuffmanSymbol(code: 0x1ffffee, len: 25),    # 234
    HuffmanSymbol(code: 0x1ffffef, len: 25),    # 235
    HuffmanSymbol(code: 0xfffff4, len: 24),     # 236
    HuffmanSymbol(code: 0xfffff5, len: 24),     # 237
    HuffmanSymbol(code: 0x3ffffea, len: 26),    # 238
    HuffmanSymbol(code: 0x7ffff4, len: 23),     # 239
    HuffmanSymbol(code: 0x3ffffeb, len: 26),    # 240
    HuffmanSymbol(code: 0x7ffffe6, len: 27),    # 241
    HuffmanSymbol(code: 0x3ffffec, len: 26),    # 242
    HuffmanSymbol(code: 0x3ffffed, len: 26),    # 243
    HuffmanSymbol(code: 0x7ffffe7, len: 27),    # 244
    HuffmanSymbol(code: 0x7ffffe8, len: 27),    # 245
    HuffmanSymbol(code: 0x7ffffe9, len: 27),    # 246
    HuffmanSymbol(code: 0x7ffffea, len: 27),    # 247
    HuffmanSymbol(code: 0x7ffffeb, len: 27),    # 248
    HuffmanSymbol(code: 0xffffffe, len: 28),    # 249
    HuffmanSymbol(code: 0x7ffffec, len: 27),    # 250
    HuffmanSymbol(code: 0x7ffffed, len: 27),    # 251
    HuffmanSymbol(code: 0x7ffffee, len: 27),    # 252
    HuffmanSymbol(code: 0x7ffffef, len: 27),    # 253
    HuffmanSymbol(code: 0x7fffff0, len: 27),    # 254
    HuffmanSymbol(code: 0x3ffffee, len: 26),    # 255
    HuffmanSymbol(code: 0x3fffffff, len: 30)    # 256 (EOS)
  ]

# ============================================================================
# Decode Tree Generation (Compile Time)
# ============================================================================

type
  DecodeNode = object
    left: int32
    right: int32

# Builds the decode tree.
# Nodes > 0 are indices into the seq.
# Nodes < 0 are leaves: symbol = -(node + 1).
proc buildDecodeTree(): seq[DecodeNode] =
  var nodes = @[DecodeNode(left: 0, right: 0)] # Root at index 0
  
  for symIdx, entry in HuffmanTable:
    var curr = 0
    # Process bits from MSB (most significant) to LSB.
    for i in countdown(entry.len - 1, 0):
      let bit = (entry.code shr i) and 1
      let isLastBit = (i == 0)
      
      if bit == 0:
        if isLastBit:
          nodes[curr].left = int32(-(symIdx + 1))
        else:
          if nodes[curr].left <= 0:
             nodes.add(DecodeNode(left: 0, right: 0))
             nodes[curr].left = int32(nodes.len - 1)
          curr = int(nodes[curr].left)
      else: # bit == 1
        if isLastBit:
          nodes[curr].right = int32(-(symIdx + 1))
        else:
          if nodes[curr].right <= 0:
             nodes.add(DecodeNode(left: 0, right: 0))
             nodes[curr].right = int32(nodes.len - 1)
          curr = int(nodes[curr].right)
          
  result = nodes

const DecodeTree = buildDecodeTree()

# Helper to identify which nodes in the tree are reachable solely by 1s (prefix of EOS).
# This is used for padding validation.
proc buildValidPaddingSet(): seq[int] =
  var valid = newSeq[int]()
  var curr = 0
  # We check up to 7 levels because padding > 7 bits is an error.
  for i in 1..7:
    let nextR = DecodeTree[curr].right
    if nextR > 0:
      curr = int(nextR)
      valid.add(curr)
    else:
      # If we hit a leaf or invalid link, stop. 
      # (Note: In standard HPACK tree, 7 ones doesn't hit a leaf yet, EOS is 30 bits)
      break
  result = valid

const ValidPaddingNodes = buildValidPaddingSet()

# ============================================================================
# Encoding
# ============================================================================

proc hpackHuffmanEncode*(data: string): seq[byte] =
  result = newSeqOfCap[byte](data.len)
  
  var 
    currentByte: uint64 = 0
    bitsUsed: int = 0
    
  for c in data:
    let sym = HuffmanTable[uint8(c)]
    let code = sym.code
    let length = sym.len
    
    # Pack bits
    currentByte = (currentByte shl length) or code
    bitsUsed += length
    
    while bitsUsed >= 8:
      bitsUsed -= 8
      result.add(byte((currentByte shr bitsUsed) and 0xFF))
      
  # Handle padding
  if bitsUsed > 0:
    # Pad with 1s to the next byte boundary
    let padLen = 8 - bitsUsed
    currentByte = (currentByte shl padLen) or ((1'u64 shl padLen) - 1)
    result.add(byte(currentByte and 0xFF))

# ============================================================================
# Decoding
# ============================================================================

proc hpackHuffmanDecode*(data: seq[byte]): string =
  result = ""
  var nodeIndex = 0
  
  for b in data:
    for i in countdown(7, 0):
      let bit = (b shr i) and 1
      
      let nextNode = if bit == 0: DecodeTree[nodeIndex].left
                     else:        DecodeTree[nodeIndex].right
                     
      if nextNode < 0:
        # Found a leaf
        let sym = -(nextNode + 1)
        if sym == EOS_SYM:
          raise newException(ValueError, "HPACK Huffman: EOS symbol found in string")
        
        result.add(char(sym))
        nodeIndex = 0
      else:
        nodeIndex = int(nextNode)
        if nodeIndex == 0: 
          raise newException(ValueError, "HPACK Huffman: Invalid code path")

  # Padding Validation
  if nodeIndex != 0:
    # We ended inside the tree (incomplete code).
    # RFC 7541: "A padding not corresponding to the most significant bits of the code 
    # for the EOS symbol MUST be treated as a decoding error."
    # Since EOS is all 1s, the path we traveled to get to 'nodeIndex' since the 
    # last symbol must consist ENTIRELY of 1s.
    # We pre-calculated the set of nodes reachable by 1s (ValidPaddingNodes).
    
    if not ValidPaddingNodes.contains(nodeIndex):
      raise newException(ValueError, "HPACK Huffman: Invalid padding")
      
    # Also, implicit check: if nodeIndex is valid, its depth is <= 7, 
    # because ValidPaddingNodes only contains nodes up to depth 7.

# ============================================================================
# Main Test Block
# ============================================================================

when isMainModule:
  proc toHexStr(s: seq[byte]): string =
    result = ""
    for b in s: result.add(toHex(b, 2))
    result = result.toLowerAscii()

  echo "Running RFC 7541 Tests..."

  # Test Case 1: "www.example.com"
  let testStr1 = "www.example.com"
  let encoded1 = hpackHuffmanEncode(testStr1)
  let expectedHex1 = "f1e3c2e5f23a6ba0ab90f4ff"
  
  if toHexStr(encoded1) == expectedHex1:
    echo "[PASS] Test 1 matches RFC"
  else:
    echo "[FAIL] Test 1 mismatch. Expected ", expectedHex1

  if hpackHuffmanDecode(encoded1) == testStr1:
    echo "[PASS] Test 1 Round trip"
  else:
    echo "[FAIL] Test 1 Round trip failed"

  # Test Case 2: "no-cache"
  let testStr2 = "no-cache"
  let encoded2 = hpackHuffmanEncode(testStr2)
  let expectedHex2 = "a8eb10649cbf"
  
  if toHexStr(encoded2) == expectedHex2:
    echo "[PASS] Test 2 matches RFC"
  else:
    echo "[FAIL] Test 2 mismatch"

  if hpackHuffmanDecode(encoded2) == testStr2:
    echo "[PASS] Test 2 Round trip"

  # Test Case 3: "custom-key"
  let testStr3 = "custom-key"
  let encoded3 = hpackHuffmanEncode(testStr3)
  let expectedHex3 = "25a849e95ba97d7f"
  
  if toHexStr(encoded3) == expectedHex3:
    echo "[PASS] Test 3 matches RFC"
  else:
    echo "[FAIL] Test 3 mismatch"

  # Test Case 4: "custom-value"
  let testStr4 = "custom-value"
  let encoded4 = hpackHuffmanEncode(testStr4)
  let expectedHex4 = "25a849e95bb8e8b4bf"
  
  if toHexStr(encoded4) == expectedHex4:
    echo "[PASS] Test 4 matches RFC"
  else:
    echo "[FAIL] Test 4 mismatch"

  # Test Case: Invalid Padding (Zeros)
  # 'a' is 00011. Input 0x18 is 00011000. 
  # Decodes 'a', then sees '000'. '000' is valid path in tree, but invalid padding (not 1s).
  try:
    discard hpackHuffmanDecode(@[byte(0x18)])
    echo "[FAIL] Invalid padding (zeros) was accepted"
  except ValueError:
    echo "[PASS] Invalid padding (zeros) correctly rejected"

  # Test Case: Invalid Padding (Ones but too long?) 
  # Note: Can't easily construct >7 bits padding error with byte-aligned input 
  # because 8 ones would be 0xFF, which might just look like incomplete code.
  # But ValidPaddingNodes logic ensures that whatever incomplete state remains
  # must be one of the specific "just 1s" states.