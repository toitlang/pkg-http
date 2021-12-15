// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader
import writer

import .headers
import .chunked
import .response
import .connection

class Request:
  connection_/Connection := ?

  method/string
  path/string
  headers/Headers
  version/string ::= "HTTP/1.1"

  body/reader.Reader? := null

  // Outgoing request to an HTTP server, we are acting like a client.
  constructor.client .connection_ .method .path .headers:
    if connection_.host:
      headers.set "Host" connection_.host

  // Incoming request from an HTTP client like a browser, we are the server.
  constructor.server .connection_ .body .method .path .version .headers:

  content_length -> int?:
    if body is ContentLengthReader:
      return (body as ContentLengthReader).content_length
    return null

  send:
    body_writer := connection_.send_headers
      "$method $path $version\r\n"
      headers
    if body:
      while data := body.read:
        body_writer.write data
    body_writer.close
    return connection_.read_response

  drain:
    while body.read:
