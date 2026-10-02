// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http.connection show Connection ContentLengthReader_ ContentLengthWriter_
import http.chunked show ChunkedReader_

import .memory-socket

main:
  test-buffering
  test-ambiguous-framing
  test-invalid-length
  test-writer-limit
  test-response-framing
  test-chunked-metadata

test-buffering:
  socket := MemorySocket ["ab".to-byte-array, "cdNEXT".to-byte-array]
  connection := Connection socket --location=null
  try:
    body := ContentLengthReader_ connection socket.in 4
    body.buffer-all
    expect-equals "abcd" body.read-all.to-string
    expect-equals "NEXT" socket.in.read-all.to-string
  finally:
    connection.close

test-response-framing:
  ["HEAD", "304", "103"].do: | kind/string |
    next := "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nx"
    first := kind == "103"
        ? "HTTP/1.1 103 Early Hints\r\n\r\n"
        : "HTTP/1.1 $(kind == "304" ? 304 : 200) Status\r\nContent-Length: 123\r\n\r\n"
    socket := MemorySocket [(first + next).to-byte-array]
    connection := Connection socket --location=null
    try:
      method := kind == "HEAD" ? "HEAD" : "GET"
      response := (connection.new-request method "/").send
      if kind == "103":
        expect-equals 200 response.status-code
      else:
        expect-equals #[] response.body.read-all
        response = (connection.new-request "GET" "/").send
      expect-equals "x" response.body.read-all.to-string
    finally:
      connection.close

test-chunked-metadata:
  socket := MemorySocket ["1;name=value\r\nx\r\n0\r\nX-Trailer: ignored\r\n\r\nNEXT".to-byte-array]
  connection := Connection socket --location=null
  try:
    reader := ChunkedReader_ connection socket.in
    expect-equals "x" reader.read-all.to-string
    expect-equals "NEXT" socket.in.read-all.to-string
  finally:
    connection.close

test-ambiguous-framing:
  [
    "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n",
    "Content-Length: 1\r\nContent-Length: 0\r\n",
    "Content-Length: 0\r\nContent-Length: 0\r\n",
  ].do: | headers/string |
    socket := MemorySocket ["POST / HTTP/1.1\r\n$headers\r\n".to-byte-array]
    connection := Connection socket --location=null
    try:
      expect-throw "INVALID_CONTENT_LENGTH": connection.read-request
    finally:
      connection.close
    response-socket := MemorySocket ["HTTP/1.1 200 OK\r\n$headers\r\n".to-byte-array]
    response-connection := Connection response-socket --location=null
    expect-throw "INVALID_CONTENT_LENGTH": response-connection.read-response
    expect response-socket.closed

test-invalid-length:
  ["-1", "+1", "1_0", "0x10", ""].do: | length/string |
    socket := MemorySocket ["POST / HTTP/1.1\r\nContent-Length: $length\r\n\r\n".to-byte-array]
    connection := Connection socket --location=null
    try:
      expect-throw "INVALID_CONTENT_LENGTH": connection.read-request
    finally:
      connection.close

test-writer-limit:
  socket := MemorySocket
  connection := Connection socket --location=null
  try:
    writer := ContentLengthWriter_ connection socket.out 2
    writer.write "ab"
    expect-throw "TOO_MUCH_WRITTEN": writer.write "c"
    expect-equals "ab" socket.out.buffer.to-string
    writer.close
  finally:
    connection.close
