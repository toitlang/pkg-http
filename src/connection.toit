// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io
import net
import net.tcp

import .chunked
import .client
import .headers
import .request
import .response
import .status-codes

class Connection:
  socket_/tcp.Socket? := null
  host_/string?
  location_/ParsedUri_? := null
  // These are writers and readers that have been given to API users.
  current-writer_/io.CloseableWriter? := null
  current-reader_/io.Reader? := null
  write-closed_ := false

  // For testing.
  call-in-finalizer_/Lambda? := null

  constructor .socket_ --location/ParsedUri_? --host/string?=null:
    host_ = host
    location_ = location
    add-finalizer this:: this.finalize_

  new-request method/string path/string headers/Headers?=null -> RequestOutgoing:
    headers = headers ? headers.copy : Headers
    if current-reader_ or current-writer_: throw "Previous request not completed"
    return RequestOutgoing.private_ this method path headers

  is-open_ -> bool:
    return socket_ != null

  close -> none:
    if socket_:
      socket_.close
      if current-writer_:
        current-writer_.close
      socket_ = null
      remove-finalizer this
      write-closed_ = true
      current-reader_ = null
      current-writer_ = null

  finalize_:
    // TODO: We should somehow warn people that they forgot to close the
    // connection.  It releases the memory earlier than relying on the
    // finalizer, so it can avoid some out-of-memory situations.
    if call-in-finalizer_ and socket_: call-in-finalizer_.call this
    close


  /**
  Deprecated.
  */
  drain -> none:
    drain_

  drain_ -> none:
    if write-closed_:
      current-reader_ = null
      close
    if current-reader_:
      current-reader_.drain
      current-reader_ = null
    if current-writer_:
      current-writer_.close
      current-writer_ = null

  /**
  Indicates to the other side that we won't be writing any more on this
    connection.  On TCP this means sending a FIN packet.
  If we are not currently reading from the connection the connection is
    completely closed.  Otherwise the connection will be closed on completing
    the current read.

  Deprecated.
  */
  close-write -> none:
    close-write_

  /**
  Indicates to the other side that we won't be writing any more on this
    connection.  On TCP this means sending a FIN packet.
  If we are not currently reading from the connection the connection is
    completely closed.  Otherwise the connection will be closed on completing
    the current read.
  */
  close-write_ -> none:
    if not current-reader_:
      close
    else if socket_:
      socket_.out.close
      write-closed_ = true

  /**
  Sends the given $headers.

  If $content-length is not given, it will be extracted from the headers.
  If neither $content-length nor a Content-Length header is given, the body
    will be sent in a chunked way.

  If both $content-length and a Content-Length header is given, they must
    match.
  */
  send-headers -> io.CloseableWriter
      status/string headers/Headers
      --is-client-request/bool
      --content-length/int?
      --has-body/bool:
    writer := socket_.out
    if current-writer_: throw "Previous request not completed"
    body-writer/io.CloseableWriter := ?
    needs-to-write-chunked-header := false

    if has-body:
      content-length-header := headers.single "Content-Length"
      if content-length-header:
        header-length := int.parse content-length-header
        if not content-length: content-length = header-length
        if content-length != header-length:
          throw "Content-Length header ($header-length) does not match content length ($content-length)"
      else if content-length:
        headers.set "Content-Length" "$content-length"

      if content-length:
        body-writer = ContentLengthWriter_ this writer content-length
      else:
        needs-to-write-chunked-header = true
        body-writer = ChunkedWriter_ this writer
    else:
      // Return a writer that doesn't accept any data.
      body-writer = ContentLengthWriter_ this writer 0
      if not headers.matches "Connection" "Upgrade":
        headers.set "Content-Length" "0"

    // Set this before doing blocking operations on the socket, so that we
    // don't let another task start another request on the same connection.
    if has-body: current-writer_ = body-writer
    socket_.no-delay = false

    writer.write status
    headers.write-to writer
    if is-client-request and host_:
      writer.write "Host: $host_\r\n"
    if needs-to-write-chunked-header:
      writer.write "Transfer-Encoding: chunked\r\n"
    writer.write "\r\n"

    socket_.no-delay = true
    return body-writer

  // Gets the next request from the client. If the client closes the
  // connection, returns null.
  read-request -> RequestIncoming?:
    // In theory HTTP/1.1 can support pipelining, but it causes issues
    // with many servers, so nobody uses it.
    if current-reader_: throw "Previous response not completed"
    if not socket_: return null

    reader := socket_.in

    if not reader.try-ensure-buffered 1:
      if write-closed_: close
      return null
    index-of-first-space := reader.index-of ' ' --throw-if-absent
    method := reader.read-string (index-of-first-space)
    reader.skip 1
    path := reader.read-string (reader.index-of ' ' --throw-if-absent)
    reader.skip 1
    version := reader.read-string (reader.index-of '\r' --throw-if-absent)
    reader.skip 1
    if reader.read-byte != '\n': throw "FORMAT_ERROR"

    headers := read-headers_
    content-length-str := headers.single "Content-Length"
    content-length := content-length-str and (int.parse content-length-str)
    current-reader_ = body-reader_ headers --request=true content-length

    body-reader := current-reader_ or ContentLengthReader_ this reader 0
    return RequestIncoming.private_ this body-reader method path version headers

  detach -> tcp.Socket:
    if not socket_: throw "ALREADY_CLOSED"
    socket := socket_
    socket_ = null
    remove-finalizer this
    return socket

  read-response -> Response:
    reader := socket_.in
    if current-reader_: throw "Previous response not completed"
    headers := null
    try:
      version := reader.read-string (reader.index-of ' ' --throw-if-absent)
      reader.skip 1
      status-code := int.parse (reader.read-string (reader.index-of ' ' --throw-if-absent))
      reader.skip 1
      status-message := reader.read-string (reader.index-of '\r' --throw-if-absent)
      reader.skip 1
      if reader.read-byte != '\n': throw "FORMAT_ERROR"

      headers = read-headers_
      content-length-str := headers.single "Content-Length"
      content-length := content-length-str and (int.parse content-length-str)
      current-reader_ = body-reader_ headers --request=false --status-code=status-code content-length

      body-reader := current-reader_ or ContentLengthReader_ this reader 0
      return Response this version status-code status-message headers body-reader

    finally:
      if not headers:
        close

  body-reader_ headers/Headers --request/bool --status-code/int?=null content-length/int? -> io.Reader?:
    reader := socket_.in
    if content-length:
      if content-length == 0: return null  // No read is needed to drain this response.
      return ContentLengthReader_ this reader content-length

    // The only transfer encodings we support are 'identity' and 'chunked',
    // which are both required by HTTP/1.1.
    T-E ::= "Transfer-Encoding"
    if headers.single T-E:
      if headers.matches T-E "chunked":
        return ChunkedReader_ this reader
      else if not headers.matches T-E "identity":
        throw "No support for $T-E: $(headers.single T-E)"

    if request or status-code == STATUS-NO-CONTENT:
      // For requests (we are the server) a missing Content-Length means a zero
      // length body.  We also do this as client if the server has explicitly
      // stated that there is no content.  We return a null reader, which means
      // the user does not need to drain the response.
      return null

    // If there is no Content-Length field (and we are not using chunked
    // transfer-encoding) we just don't know the size of the transfer.
    // The server will indicate the end by closing.  TODO: Distinguish
    // between FIN closes and RST closes so we can know whether the
    // transfer succeeded.  Incidentally this also means the connection
    // can't be reused, but that should happen automatically because it
    // is closed.
    return UnknownContentLengthReader_ this reader

  // Optional whitespace is spaces and tabs.
  is-whitespace_ char:
    return char == ' ' or char == '\t'

  read-headers_:
    reader := socket_.in
    headers := Headers

    while (reader.peek-byte 0) != '\r':
      if is-whitespace_ (reader.peek-byte 0):
        // Line folded headers are deprecated in RFC 7230 and we don't support
        // them.
        throw "FOLDED_HEADER"
      key := reader.read-string (reader.index-of ':')
      reader.skip 1

      while is-whitespace_ (reader.peek-byte 0): reader.skip 1

      value := reader.read-string (reader.index-of '\r')
      reader.skip 1
      if reader.read-byte != '\n': throw "FORMAT_ERROR"

      headers.add key value

    reader.skip 1
    if reader.read-byte != '\n': throw "FORMAT_ERROR"

    return headers

  reading-done_ reader/io.Reader:
    if current-reader_:
      if reader != current-reader_: throw "Read from reader that was already done"
      current-reader_ = null
      if write-closed_: close

  writing-done_ writer/io.Writer:
    if current-writer_:
      if writer != current-writer_: throw "Close of a writer that was already done"
      current-writer_ = null

/**
Deprecated for public use. Use the type $io.Reader instead.
This class will be made private in the future.
*/
class ContentLengthReader extends ContentLengthReader_:
  constructor connection/Connection reader/io.Reader size/int:
    super connection reader size

class ContentLengthReader_ extends io.Reader:
  connection_/Connection
  reader_/io.Reader
  read-from-wrapped_/int := 0

  content-size/int

  constructor .connection_ .reader_ .content-size:

  /**
  Deprecated. Use $content-size instead.
  */
  content-length -> int:
    return content-size

  read_ -> ByteArray?:
    if read-from-wrapped_ >= content-size:
      connection_.reading-done_ this
      return null
    data := reader_.read --max-size=(content-size - processed)
    if not data:
      connection_.close
      throw io.Reader.UNEXPECTED-END-OF-READER
    read-from-wrapped_ += data.size
    return data

/**
Deprecated for public use. Use the type $io.Reader instead.
This class will be made private in the future.
*/
class UnknownContentLengthReader extends UnknownContentLengthReader_:
  constructor connection/Connection reader/io.Reader:
    super connection reader

class UnknownContentLengthReader_ extends io.Reader:
  connection_/Connection
  reader_/io.Reader

  constructor .connection_ .reader_:

  read_ -> ByteArray?:
    data := reader_.read
    if not data:
      connection_.close  // After an unknown content length the connection must close.
      return null
    return data

/**
Deprecated for public use. Use the type $io.CloseableWriter instead.
*/
interface BodyWriter:
  write data -> int
  is-done -> bool
  close -> none

/**
Deprecated for public use. Use the type $io.CloseableWriter instead.
This class will be made private in the future.
*/
class ContentLengthWriter extends ContentLengthWriter_:
  constructor connection/Connection writer/io.Writer content-length/int:
    super connection writer content-length

class ContentLengthWriter_ extends io.CloseableWriter implements BodyWriter:
  connection_/Connection? := null
  writer_/io.Writer
  content-length_/int := ?
  written-to-wrapped_/int := 0

  constructor .connection_ .writer_ .content-length_:

  is-done -> bool:
    return written-to-wrapped_ >= content-length_

  try-write_ data/io.Data from/int to/int -> int:
    result := writer_.try-write data from to
    written-to-wrapped_ += result
    return result

  close_ -> none:
    if connection_:
      connection_.writing-done_ this
    connection_ = null

is-close-exception_ exception -> bool:
  return exception == io.Reader.UNEXPECTED-END-OF-READER
      or exception == "Broken pipe"
      or exception == "Connection reset by peer"
      or exception == "NOT_CONNECTED"
      or exception == "Connection closed"
      or (exception is string and exception.contains "connection was aborted")
      or (exception is string and exception.contains "connection was forcibly closed")
