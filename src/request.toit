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

  is_client_request_/bool := ?

  // Outgoing request to an HTTP server, we are acting like a client.
  constructor.client .connection_ .method .path .headers:
    is_client_request_ = true

  // Incoming request from an HTTP client like a browser, we are the server.
  constructor.server .connection_ .body .method .path .version .headers:
    is_client_request_ = false

  content_length -> int?:
    if body is ContentLengthReader:
      return (body as ContentLengthReader).content_length
    return null

  send -> Response:
    slash := (path.starts_with "/") ? "" : "/"
    body_writer := connection_.send_headers
        "$method $slash$path $version\r\n"
        headers
        --is_client_request=is_client_request_
        --has_body=(body != null)
    if body:
      while data := body.read:
        body_writer.write data
    body_writer.close
    return connection_.read_response

  drain:
    while body.read:
