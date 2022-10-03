// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

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

  stringify: return "$status_code: $status_message"

  // Return a reader & writer object, used to send raw data on the connection.
  detach -> tcp.Socket:
    return DetachedSocket_ connection_.socket_ body
