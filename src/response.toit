// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import net
import net.tcp
import reader
import writer

import .connection
import .headers
import .chunked
import .request

class Response:
  connection_/Connection
  headers ::= Headers
  version/string
  status_code/int
  status_message/string
  body/reader.Reader

  constructor .connection_ .version .status_code .status_message .headers .body:

  // Return a reader & writer object, used to send raw data on the connection.
  detach -> tcp.Socket:
    return DetachedSocket connection_.socket_ body

class DetachedSocket implements tcp.Socket:
  socket_/tcp.Socket
  reader_/reader.Reader?

  constructor .socket_ .reader_:

  read -> ByteArray?: return reader_.read
  write data from=0 to=data.size: return socket_.write data from to
  close_write: return socket_.close_write
  close: return socket_.close
  local_address -> net.SocketAddress: return socket_.local_address
  peer_address -> net.SocketAddress: return socket_.peer_address
  set_no_delay enabled/bool: socket_.set_no_delay enabled
  mtu -> int: return socket_.mtu
