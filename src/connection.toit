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
import .status_codes

class Connection:
  socket_/tcp.Socket? := null
  host_/string?
  location_/ParsedUri_? := null
  // These are writers and readers that have been given to API users.
  current_writer_/io.CloseableWriter? := null
  // TODO(florian): should this be a closeable reader?
  current_reader_/io.Reader? := null
  write_closed_ := false

  // For testing.
  call_in_finalizer_/Lambda? := null

  constructor .socket_ --location/ParsedUri_? --host/string?=null:
    host_ = host
    location_ = location
    add_finalizer this:: this.finalize_

  new_request method/string path/string headers/Headers?=null -> RequestOutgoing:
    headers = headers ? headers.copy : Headers
    if current_reader_ or current_writer_: throw "Previous request not completed"
    return RequestOutgoing.private_ this method path headers

  is_open_ -> bool:
    return socket_ != null

  close -> none:
    if socket_:
      socket_.close
      // TODO(florian): should we close the writer?
      if current_writer_:
        current_writer_.close
      // TODO(florian): should current_reader be closeable and be closed here?
      socket_ = null
      remove_finalizer this
      write_closed_ = true
      current_reader_ = null
      current_writer_ = null

  finalize_:
    // TODO: We should somehow warn people that they forgot to close the
    // connection.  It releases the memory earlier than relying on the
    // finalizer, so it can avoid some out-of-memory situations.
    if call_in_finalizer_ and socket_: call_in_finalizer_.call this
    close

  drain -> none:
    if write_closed_:
      current_reader_ = null
      close
    if current_reader_:
      // TODO(florian): should reader be closeable and be closed here?
      current_reader_.drain
      current_reader_ = null
    if current_writer_:
      current_writer_.close
      current_writer_ = null

  /**
  Indicates to the other side that we won't be writing any more on this
    connection.  On TCP this means sending a FIN packet.
  If we are not currently reading from the connection the connection is
    completely closed.  Otherwise the connection will be closed on completing
    the current read.
  */
  close_write -> none:
    if not current_reader_:
      close
    else if socket_:
      socket_.out.close
      write_closed_ = true

  /**
  Sends the given $headers.

  If $content_length is not given, it will be extracted from the headers.
  If neither $content_length nor a Content-Length header is given, the body
    will be sent in a chunked way.

  If both $content_length and a Content-Length header is given, they must
    match.
  */
  send_headers -> io.CloseableWriter
      status/string headers/Headers
      --is_client_request/bool
      --content_length/int?
      --has_body/bool:
    writer := socket_.out
    if current_writer_: throw "Previous request not completed"
    body_writer/io.CloseableWriter := ?
    needs_to_write_chunked_header := false

    if has_body:
      content_length_header := headers.single "Content-Length"
      if content_length_header:
        header_length := int.parse content_length_header
        if not content_length: content_length = header_length
        if content_length != header_length:
          throw "Content-Length header ($header_length) does not match content length ($content_length)"
      else if content_length:
        headers.set "Content-Length" "$content_length"

      if content_length:
        body_writer = ContentLengthWriter this writer content_length
      else:
        needs_to_write_chunked_header = true
        body_writer = ChunkedWriter this writer
    else:
      // Return a writer that doesn't accept any data.
      body_writer = ContentLengthWriter this writer 0
      if not headers.matches "Connection" "Upgrade":
        headers.set "Content-Length" "0"

    // Set this before doing blocking operations on the socket, so that we
    // don't let another task start another request on the same connection.
    if has_body: current_writer_ = body_writer
    socket_.no_delay = false

    writer.write status
    headers.write_to writer
    if is_client_request and host_:
      writer.write "Host: $host_\r\n"
    if needs_to_write_chunked_header:
      writer.write "Transfer-Encoding: chunked\r\n"
    writer.write "\r\n"

    socket_.no_delay = true
    return body_writer

  // Gets the next request from the client. If the client closes the
  // connection, returns null.
  read_request -> RequestIncoming?:
    // In theory HTTP/1.1 can support pipelining, but it causes issues
    // with many servers, so nobody uses it.
    if current_reader_: throw "Previous response not completed"
    if not socket_: return null

    reader := socket_.in

    if not reader.try-ensure-buffered 1:
      if write_closed_: close
      return null
    index_of_first_space := reader.index_of ' ' --throw-if-missing
    method := reader.read_string (index_of_first_space)
    reader.skip 1
    path := reader.read_string (reader.index_of ' ' --throw-if-missing)
    reader.skip 1
    version := reader.read_string (reader.index_of '\r' --throw-if-missing)
    reader.skip 1
    if reader.read_byte != '\n': throw "FORMAT_ERROR"

    headers := read_headers_
    content_length_str := headers.single "Content-Length"
    content_length := content_length_str and (int.parse content_length_str)
    current_reader_ = body_reader_ headers --request=true content_length

    body_reader := current_reader_ or ContentLengthReader this reader 0
    return RequestIncoming.private_ this body_reader method path version headers

  detach -> tcp.Socket:
    if not socket_: throw "ALREADY_CLOSED"
    socket := socket_
    socket_ = null
    remove_finalizer this
    return socket

  read_response -> Response:
    reader := socket_.in
    if current_reader_: throw "Previous response not completed"
    headers := null
    try:
      version := reader.read_string (reader.index_of ' ' --throw-if-missing)
      reader.skip 1
      status_code := int.parse (reader.read_string (reader.index_of ' ' --throw-if-missing))
      reader.skip 1
      status_message := reader.read_string (reader.index_of '\r' --throw-if-missing)
      reader.skip 1
      if reader.read_byte != '\n': throw "FORMAT_ERROR"

      headers = read_headers_
      content_length_str := headers.single "Content-Length"
      content_length := content_length_str and (int.parse content_length_str)
      current_reader_ = body_reader_ headers --request=false --status_code=status_code content-length

      body_reader := current_reader_ or ContentLengthReader this reader 0
      return Response this version status_code status_message headers body_reader

    finally:
      if not headers:
        close

  body_reader_ headers/Headers --request/bool --status_code/int?=null content_length/int? -> io.Reader?:
    reader := socket_.in
    if content_length:
      if content_length == 0: return null  // No read is needed to drain this response.
      return ContentLengthReader this reader content_length

    // The only transfer encodings we support are 'identity' and 'chunked',
    // which are both required by HTTP/1.1.
    T_E ::= "Transfer-Encoding"
    if headers.single T_E:
      if headers.matches T_E "chunked":
        return ChunkedReader this reader
      else if not headers.matches T_E "identity":
        throw "No support for $T_E: $(headers.single T_E)"

    if request or status_code == STATUS_NO_CONTENT:
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
    return UnknownContentLengthReader this reader

  // Optional whitespace is spaces and tabs.
  is_whitespace_ char:
    return char == ' ' or char == '\t'

  read_headers_:
    reader := socket_.in
    headers := Headers

    while (reader.peek-byte 0) != '\r':
      if is_whitespace_ (reader.peek-byte 0):
        // Line folded headers are deprecated in RFC 7230 and we don't support
        // them.
        throw "FOLDED_HEADER"
      key := reader.read_string (reader.index_of ':')
      reader.skip 1

      while is_whitespace_ (reader.peek-byte 0): reader.skip 1

      value := reader.read_string (reader.index_of '\r')
      reader.skip 1
      if reader.read_byte != '\n': throw "FORMAT_ERROR"

      headers.add key value

    reader.skip 1
    if reader.read_byte != '\n': throw "FORMAT_ERROR"

    return headers

  reading_done_ reader/io.Reader:
    if current_reader_:
      if reader != current_reader_: throw "Read from reader that was already done"
      current_reader_ = null
      if write_closed_: close

  writing_done_ writer/io.Writer:
    if current_writer_:
      if writer != current_writer_: throw "Close of a writer that was already done"
      current_writer_ = null

/**
Deprecated. Use the type $io.Reader instead.
This class will be made private in the future.
*/
class ContentLengthReader extends Object with io.Reader:
  connection_/Connection
  reader_/io.Reader

  size/int

  constructor .connection_ .reader_ .size:

  /**
  Deprecated. Use $size instead.
  */
  content_length -> int:
    return size

  consume_ -> ByteArray?:
    if consumed >= size:
      connection_.reading_done_ this
      return null
    data := reader_.read --max_size=(size - consumed)
    if not data:
      connection_.close
      throw io.Reader.UNEXPECTED_END_OF_READER
    return data

/**
Deprecated. Use the type $io.Reader instead.
This class will be made private in the future.
*/
class UnknownContentLengthReader extends Object with io.Reader:
  connection_/Connection
  reader_/io.Reader

  constructor .connection_ .reader_:

  consume_ -> ByteArray?:
    data := reader_.read
    if not data:
      connection_.close  // After an unknown content length the connection must close.
      return null
    return data

/**
Deprecated. Use the type $io.CloseableWriter instead.
*/
interface BodyWriter:
  write data -> int
  is_done -> bool
  close -> none

/**
Deprecated. Use the type $io.CloseableWriter instead.
This class will be made private in the future.
*/
class ContentLengthWriter extends Object with io.CloseableWriter implements BodyWriter:
  connection_/Connection? := null
  writer_/io.Writer
  content_length_/int := ?

  constructor .connection_ .writer_ .content_length_:

  is_done -> bool:
    return written >= content_length_

  try_write_ data/io.Data from/int to/int -> int:
    return writer_.try_write data from to

  close_ -> none:
    if connection_:
      connection_.writing_done_ this
    connection_ = null

is_close_exception_ exception -> bool:
  return exception == io.Reader.UNEXPECTED_END_OF_READER
      or exception == "Broken pipe"
      or exception == "Connection reset by peer"
      or exception == "NOT_CONNECTED"
      or exception == "Connection closed"
      or (exception is string and exception.contains "connection was aborted")
      or (exception is string and exception.contains "connection was forcibly closed")
