// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import http.connection show Connection
import io
import log
import net.tcp

import .memory-socket show MemoryReader

WRITE-ERROR ::= "synthetic write failure"
SHUTDOWN-ERROR ::= "synthetic shutdown failure"
CLOSE-ERROR ::= "synthetic close failure"

class FaultWriter extends io.CloseableWriter:
  buffer/io.Buffer ::= io.Buffer
  on-write/Lambda? := null
  on-close/Lambda? := null
  transport-closed/bool := false
  block-write/bool := false
  fail-write/bool := false
  writes/int := 0
  fail-at/int := -1
  fail-close/bool := false

  try-write_ data/io.Data from/int to/int -> int:
    if action := on-write:
      on-write = null
      action.call
    if block-write: sleep --ms=1000
    if fail-write or writes++ == fail-at: throw WRITE-ERROR
    return buffer.write data from to

  close_:
    if action := on-close:
      on-close = null
      action.call
    if transport-closed: throw CLOSE-ERROR
    if fail-close: throw SHUTDOWN-ERROR

class FaultSocket implements tcp.Socket:
  in/MemoryReader
  out/FaultWriter ::= FaultWriter
  no-delay/bool := true
  closed/bool := false
  fail-close/bool := false
  closes/int := 0

  constructor chunks/List=[]:
    in = MemoryReader chunks

  local-address: unreachable
  peer-address: unreachable
  mtu: return 1500
  read: return in.read
  write data from=0 to=data.byte-size: return out.write data from to
  close-write: out.close
  close:
    closes++
    closed = true
    out.transport-closed = true
    if fail-close: throw CLOSE-ERROR

main args:
  failures := []
  tests := {
    "websocket shutdown": :: test-websocket-shutdown,
    "websocket active shutdown": :: test-websocket-shutdown --active,
    "websocket half shutdown": :: test-websocket-shutdown --active --half,
    "websocket normal half close": :: test-websocket-half-close,
    "websocket concurrent close": :: test-websocket-concurrent-close,
    "websocket concurrent shutdown": :: test-websocket-concurrent-close --during-shutdown,
    "websocket write timeout": :: test-websocket-timeout,
    "websocket queued ping": :: test-websocket-queued-ping,
    "websocket transport close": :: test-websocket-transport-close,
    "websocket header": :: test-websocket-header,
    "websocket payload": :: test-websocket-payload,
    "websocket streaming payload": :: test-websocket-payload --streaming,
    "websocket final fragment": :: test-websocket-final,
    "websocket incomplete writer": :: test-websocket-incomplete,
    "websocket ping": :: test-websocket-ping,
    "response detach": :: test-response-detach,
    "response detached close": :: test-response-detach --close-first,
    "response error close": :: test-response-error-close,
    "response close after error": :: test-response-error-close --close-first,
    "response failed detach": :: test-response-failed-detach,
    "detached handler failure": :: test-detached-handler,
    "connection shutdown": :: test-connection-shutdown,
    "connection transport close": :: test-connection-close,
  }
  tests.do: | name/string test/Lambda |
    if not args.is-empty and args[0].starts-with "--case=":
      if args[0] != "--case=$name": continue.do
    error := catch: test.call
    print "$name: $(error or "passed")"
    if error: failures.add name
  expect failures.is-empty --message="$failures"

expect-released websocket/http.WebSocket:
  expect-null websocket.current-writer_
  with-timeout --ms=100: websocket.writer-semaphore_.down
  expect-throw DEADLINE-EXCEEDED-ERROR:
    with-timeout --ms=10: websocket.writer-semaphore_.down
  websocket.writer-semaphore_.up

expect-aborted socket/FaultSocket websocket/http.WebSocket:
  expect socket.closed
  expect-released websocket
  expect-throw "ALREADY_CLOSED":
    with-timeout --ms=100: websocket.send "later"
  expect-released websocket
  websocket.close
  expect-null websocket.receive

// A failed half-close must still release the transport and any active writer.
test-websocket-shutdown --active/bool=false --half/bool=false:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  if active: websocket.start-sending
  socket.out.fail-close = true
  expect-throw SHUTDOWN-ERROR:
    if half: websocket.close-write
    else: websocket.close
  expect-aborted socket websocket

test-websocket-transport-close:
  socket := FaultSocket [#[0x01, 1, 'a']]
  websocket := http.WebSocket socket --no-client
  websocket.start-receiving
  socket.fail-close = true
  expect-throw CLOSE-ERROR: websocket.close
  expect-null websocket.current-reader_
  expect-released websocket

test-websocket-header:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  socket.out.fail-write = true
  expect-throw WRITE-ERROR: websocket.start-sending --size=1 --opcode=1
  expect-aborted socket websocket

test-websocket-payload --streaming/bool=false:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  if streaming:
    writer := websocket.start-sending --size=1 --opcode=1
    socket.out.fail-write = true
    expect-throw WRITE-ERROR: writer.write "a"
  else:
    socket.out.fail-at = 1  // Fail the payload after send's header succeeds.
    expect-throw WRITE-ERROR: websocket.send "b"
  expect-aborted socket websocket

test-websocket-final:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  writer := websocket.start-sending
  writer.write "a"
  socket.out.fail-write = true
  expect-throw WRITE-ERROR: writer.close
  expect-aborted socket websocket

test-websocket-incomplete:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  writer := websocket.start-sending --size=2 --opcode=1
  writer.write "a"
  expect-throw "TOO_LITTLE_WRITTEN": writer.close
  expect-aborted socket websocket

test-websocket-ping:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  socket.out.fail-write = true
  expect-throw WRITE-ERROR: websocket.ping "a"
  expect-aborted socket websocket

new-request-connection socket/FaultSocket -> Connection:
  socket.in.chunks_.add "GET / HTTP/1.1\r\n\r\n".to-byte-array
  return Connection socket --location=null

test-response-detach --close-first/bool=false:
  socket := FaultSocket
  connection := new-request-connection socket
  writer := http.ResponseWriter connection connection.read-request log.default
  writer.write-headers http.STATUS-SWITCHING-PROTOCOLS
  detached := writer.detach
  bytes := socket.out.buffer.size
  if close-first: writer.close
  expect (writer.close-on-exception_ "synthetic handler error")
  writer.close
  expect-not socket.closed
  expect-equals bytes socket.out.buffer.size
  expect-throw "ALREADY_CLOSED": writer.detach
  detached.close

test-response-error-close --close-first/bool=false:
  socket := FaultSocket
  connection := new-request-connection socket
  writer := http.ResponseWriter connection connection.read-request log.default
  writer.out.write "a"
  expect (writer.close-on-exception_ "synthetic handler error")
  if close-first: writer.close
  expect (writer.close-on-exception_ "second error")
  writer.close
  expect socket.closed

test-response-failed-detach:
  socket := FaultSocket
  connection := new-request-connection socket
  writer := http.ResponseWriter connection connection.read-request log.default
  connection.close
  expect-throw "ALREADY_CLOSED": writer.detach
  expect-not writer.detached_
  writer.close

test-detached-handler:
  socket := FaultSocket
  connection := new-request-connection socket
  server := http.Server
  expect-throw "synthetic handler error":
    server.run-connection_ connection (:: | request writer/http.ResponseWriter |
      writer.write-headers http.STATUS-SWITCHING-PROTOCOLS
      writer.detach
      throw "synthetic handler error"
    ) log.default
  expect-not socket.closed
  expect-equals 0 server.handling-count_
  socket.close

test-connection-shutdown:
  socket := FaultSocket ["POST / HTTP/1.1\r\nContent-Length: 1\r\n\r\na".to-byte-array]
  connection := Connection socket --location=null
  connection.read-request
  socket.out.fail-close = true
  expect-throw SHUTDOWN-ERROR: connection.close-write_
  expect socket.closed
  expect-not connection.is-open_
  connection.close

test-connection-close:
  socket := FaultSocket
  connection := Connection socket --location=null
  connection.send-headers "HTTP/1.1 200 OK\r\n" (http.Headers)
      --is-client-request=false
      --content-length=1
      --has-body=true
  socket.fail-close = true
  expect-throw CLOSE-ERROR: connection.close
  expect-not connection.is-open_
  expect-null connection.current-writer_
  expect-null connection.current-reader_
  connection.close
  expect-equals 1 socket.closes

// A successful half-close keeps the read direction usable.
test-websocket-half-close:
  socket := FaultSocket [#[0x81, 1, 'a']]
  websocket := http.WebSocket socket --no-client
  writer := websocket.start-sending
  websocket.close-write
  expect-not socket.closed
  expect-equals "a" websocket.receive
  expect-released websocket
  expect-throw "WRITER_CLOSED": writer.write "b"
  writer.close
  websocket.close-write
  websocket.close
  expect-equals 1 socket.closes
  expect-released websocket

test-websocket-timeout:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  writer := websocket.start-sending
  socket.out.block-write = true
  expect-throw DEADLINE-EXCEEDED-ERROR:
    with-timeout --ms=10: writer.write "a"
  expect-aborted socket websocket

test-websocket-queued-ping:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  writer := websocket.start-sending --size=1 --opcode=1
  websocket.ping "a"
  socket.out.fail-at = 2  // Message header and payload succeed, then ping fails.
  expect-throw WRITE-ERROR: writer.write "b"
  expect-aborted socket websocket

// Full close can run while another task is sending the half-close frame.
test-websocket-concurrent-close --during-shutdown/bool=false:
  socket := FaultSocket
  websocket := http.WebSocket socket --no-client
  if during-shutdown:
    socket.out.on-close = :: websocket.close
  else:
    socket.out.on-write = :: websocket.close
  with-timeout --ms=100: websocket.close-write
  expect socket.closed
  expect-equals 1 socket.closes
  expect-released websocket
