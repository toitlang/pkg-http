

// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader
import writer

import .connection
import .headers
import .chunked
import .request

class Response implements reader.Reader:
  connection_/Connection
  reader_/reader.Reader
  headers ::= Headers
  version/string
  status_code/int
  status_message/string

  constructor.client .connection_ .reader_ .version .status_code .status_message .headers:

  // Return a reader & writer object, used to send raw data on the connection.
  detach:
    return DetachedSocket reader_ connection_.socket_

  read:
    data := reader_.read
    if data: return data
    if connection_.auto_close_: connection_.close
    return null

class DetachedSocket:
  reader_ := ?
  writer_ := ?
  socket_ := ?

  constructor .reader_ .socket_:
    writer_ = writer.Writer socket_

  read:
    return reader_.read

  write data from = 0 to = data.size:
    return writer_.write data from to

  close_write:
    return socket_.close_write

  close:
    return socket_.close
