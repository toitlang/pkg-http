// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import io

import .memory-socket

main:
  test-fresh-masks
  test-lengths
  test-slices
  test-controls
  test-fixed-control
  test-pong
  test-server-frames

// Decode the wire bytes independently of the package's fragment reader.
frames transport/MemorySocket --masked/bool=true -> List:
  reader := io.Reader transport.out.buffer.bytes
  result := []
  while reader.try-ensure-buffered 1:
    control := reader.read-byte
    length-byte := reader.read-byte
    expect-equals masked ((length-byte & 0x80) != 0)
    size := length-byte & 0x7f
    if size == 126: size = reader.big-endian.read-uint16
    else if size == 127: size = reader.big-endian.read-int64
    mask := masked ? (reader.read-bytes 4) : null
    payload := reader.read-bytes size
    if mask:
      payload.size.repeat: payload[it] ^= mask[it & 3]
    result.add [control, mask, payload]
  return result

test-fresh-masks:
  transport := MemorySocket
  socket := http.WebSocket transport --client
  8.repeat: socket.send "test"
  decoded := frames transport
  expect-equals 8 decoded.size
  masks := {}
  decoded.do: | frame/List |
    masks.add (io.BIG-ENDIAN.uint32 frame[1] 0)
    expect-equals "test" frame[2].to-string
  // A constant key must fail. Eight independent keys all matching has a
  // probability of 2^-224, so this does not reject an occasional zero key.
  expect masks.size > 1

test-lengths:
  [0, 1, 125, 126, 65535, 65536].do: | size/int |
    transport := MemorySocket
    transport.out.max-write-size = 3
    socket := http.WebSocket transport --client
    payload := ByteArray size: it & 0xff
    socket.send payload
    decoded := frames transport
    expect-equals 1 decoded.size
    expect-equals 0x82 decoded[0][0]
    expect-equals payload decoded[0][2]
    // Masking must not modify the caller's buffer.
    payload.size.repeat: expect-equals (it & 0xff) payload[it]

test-slices:
  transport := MemorySocket
  transport.out.max-write-size = 1
  socket := http.WebSocket transport --client
  writer := socket.start-sending --size=4
  text := "A€BC"
  // Split a UTF-8 sequence across writes and start at a nonzero byte offset.
  writer.write text 1 3
  writer.write text 3 5
  writer.close
  decoded := frames transport
  expect-equals 1 decoded.size
  expect-equals 0x81 decoded[0][0]
  expect-equals "€B" decoded[0][2].to-string

test-controls:
  transport := MemorySocket
  transport.out.max-write-size = 2
  socket := http.WebSocket transport --client
  socket.ping "before"
  writer := socket.start-sending
  writer.write ("a" * 130)
  socket.ping "during"
  writer.write ("b" * 130)
  writer.close
  socket.close-write
  decoded := frames transport
  expect-equals [0x89, 0x01, 0x00, 0x89, 0x00, 0x00, 0x80, 0x88]
      decoded.map: it[0]
  expect-equals ["before", "a" * 125, "a" * 5, "during", "b" * 125, "b" * 5, ""]
      decoded[..7].map: it[2].to-string
  expect-equals #[3, 232] decoded[7][2]

test-server-frames:
  transport := MemorySocket
  socket := http.WebSocket transport --no-client
  socket.send "server"
  decoded := frames transport --no-masked
  expect-equals "server" decoded[0][2].to-string

test-fixed-control:
  transport := MemorySocket
  socket := http.WebSocket transport --client
  writer := socket.start-sending --size=7
  writer.write "abc"
  socket.ping "queued"
  writer.write "defg"
  writer.close
  decoded := frames transport
  expect-equals [0x81, 0x89] (decoded.map: it[0])
  expect-equals ["abcdefg", "queued"] (decoded.map: it[2].to-string)

test-pong:
  transport := MemorySocket [#[0x89, 1, 'p', 0x81, 1, 'x']]
  socket := http.WebSocket transport --client
  expect-equals "x" socket.receive
  decoded := frames transport
  expect-equals 1 decoded.size
  expect-equals 0x8a decoded[0][0]
  expect-equals "p" decoded[0][2].to-string
