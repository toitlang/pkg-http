// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http

import .memory-socket

main:
  test-ping-semaphore
  test-close-semaphore
  test-empty-continuation
  test-masked-terminator

expect-one-permit socket/http.WebSocket:
  socket.writer-semaphore_.down
  expect-throw DEADLINE-EXCEEDED-ERROR:
    with-timeout --ms=10: socket.writer-semaphore_.down
  socket.writer-semaphore_.up

test-ping-semaphore:
  socket := http.WebSocket (MemorySocket) --no-client
  socket.ping "hello"
  expect-one-permit socket

test-close-semaphore:
  socket := http.WebSocket (MemorySocket) --no-client
  socket.close-write
  expect-one-permit socket

test-empty-continuation:
  // Two empty non-final fragments followed by the final text payload.
  socket := http.WebSocket (MemorySocket [#[0x01, 0, 0x00, 0, 0x80, 1, 'x']]) --client
  expect-equals "x" socket.receive

test-masked-terminator:
  transport := MemorySocket
  socket := http.WebSocket transport --client
  writer := socket.start-sending
  writer.write "x"
  writer.close
  bytes := transport.out.buffer.bytes
  // The first frame contains its two header bytes, four mask bytes and x.
  expect-equals 13 bytes.size
  expect-equals 0x80 bytes[7]
  expect-equals 0x80 bytes[8]
