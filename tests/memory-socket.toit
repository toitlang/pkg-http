// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import io
import net
import net.tcp

class MemorySocket implements tcp.Socket:
  in/MemoryReader
  out/MemoryWriter ::= MemoryWriter
  no-delay/bool := true
  closed/bool := false

  constructor chunks/List=[]:
    in = MemoryReader chunks

  local-address -> net.SocketAddress: unreachable
  peer-address -> net.SocketAddress: unreachable
  mtu -> int: return 1500
  read -> ByteArray?: return in.read
  write data/io.Data from/int=0 to/int=data.byte-size -> int:
    return out.write data from to
  close-write: out.close
  close:
    closed = true
    in.close
    out.close

class MemoryReader extends io.CloseableReader:
  chunks_/List
  index_ := 0

  constructor .chunks_:

  read_ -> ByteArray?:
    if index_ == chunks_.size: return null
    return chunks_[index_++]

  close_:
    index_ = chunks_.size

class MemoryWriter extends io.CloseableWriter:
  buffer/io.Buffer ::= io.Buffer
  max-write-size/int? := null

  try-write_ data/io.Data from/int to/int -> int:
    if max-write-size: to = min to (from + max-write-size)
    return buffer.write data from to

  close_:

class ScriptedNetwork implements tcp.Interface:
  sockets_/List
  index_ := 0

  constructor .sockets_:

  tcp-connect host/string port/int -> tcp.Socket:
    return sockets_[index_++]

  tcp-connect address/net.SocketAddress -> tcp.Socket: unreachable
  tcp-listen port/int -> tcp.ServerSocket: unreachable
