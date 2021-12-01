
import reader
import writer

import .headers
import .chunked
import .response
import .connection

class Request implements reader.Reader:
  connection_/Connection := ?
  reader_ := null

  method/string
  path/string
  version/string ::= "HTTP/1.1"
  headers/Headers ::= Headers

  body/reader.Reader? := null

  // Outgoing request to an HTTP server, we are acting like a client.
  constructor.client .connection_ .method .path:
    if connection_.host:
      headers.set "Host" connection_.host

  // Incoming request from an HTTP client like a browser, we are the server.
  constructor.server .connection_ .reader_ .method .path .version .headers:

  send:
    body_writer := connection_.send_headers
      "$method $path $version\r\n"
      headers
    if body:
      while data := body.read:
        body_writer.write data
    body_writer.close
    return connection_.read_response

  read -> ByteArray?:
    return reader_.read

  drain:
    while read:
