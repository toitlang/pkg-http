// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show expect expect-equals
import http
import io
import net
import net.tcp

PEER-ERROR ::= "Transport endpoint is not connected"
NEXT-ACCEPT-ERROR ::= "Reached next accept"

main:
  socket := ResetSocket
  server-socket := ResetThenFailServerSocket socket
  server := http.Server

  error := catch:
    server.listen server-socket:: | request writer |
      unreachable

  expect-equals NEXT-ACCEPT-ERROR error
  expect socket.closed

class ResetThenFailServerSocket implements tcp.ServerSocket:
  socket_/tcp.Socket
  first-accept_/bool := true

  constructor .socket_:

  local-address -> net.SocketAddress:
    unreachable

  accept -> tcp.Socket?:
    if first-accept_:
      first-accept_ = false
      return socket_
    throw NEXT-ACCEPT-ERROR

  close:
    unreachable

class ResetSocket implements tcp.Socket:
  closed/bool := false

  local-address -> net.SocketAddress:
    unreachable

  peer-address -> net.SocketAddress:
    throw PEER-ERROR

  no-delay -> bool:
    unreachable

  no-delay= value/bool:
    unreachable

  in -> io.CloseableReader:
    unreachable

  out -> io.CloseableWriter:
    unreachable

  read -> ByteArray?:
    unreachable

  write data/io.Data from/int=0 to/int=data.byte-size -> int:
    unreachable

  mtu -> int:
    unreachable

  close-write:
    unreachable

  close:
    closed = true
