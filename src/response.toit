// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import net.tcp

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

  /**
  A reader that can be used to read the body of the response.
  You must read to the end of the response (body.read returns null) before
    you can reuse the connection.
  */
  body/io.Reader

  constructor .connection_ .version .status_code .status_message .headers .body:

  /**
  The length of the response body, if known.
  */
  content_length -> int?:
    return body.size

  stringify: return "$status_code: $status_message"

  // Return a reader & writer object, used to send raw data on the connection.
  detach -> tcp.Socket:
    return connection_.detach

  /**
  Drains the response body, discarding the data, so that the connection can be
    reused.
  The HTTP protocol requires that the body is drained before the connection
    can be used for something else, even if you no longer care about the body.
  As an alternative, for very large responses, you can close the client and
    create a new one.
  */
  drain -> none:
    catch: body.drain
