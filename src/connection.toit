// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader
import writer
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
  // Internal reader and writer that are used for the socket.
  reader_ := ?
  writer_/writer.Writer
  // These are writers and readers that have been given to API users.
  current_writer_ := null
  current_reader_/reader.Reader? := null
  write_closed_ := false

  // For testing.
  call_in_finalizer_/Lambda? := null

  constructor .socket_ --location/ParsedUri_? --host/string?=null:
    host_ = host
    location_ = location
    reader_ = reader.BufferedReader socket_
    writer_ = writer.Writer socket_
    add_finalizer this:: this.finalize_

  new_request method/string path/string headers/Headers -> RequestOutgoing:
    if current_reader_ or current_writer_: throw "Previous request not completed"
    return RequestOutgoing.private_ this method path headers

  is_open_:
    return socket_ != null

  close:
    if socket_:
      socket_.close
      if current_writer_:
        current_writer_.close
      socket_ = null
      remove_finalizer this
      write_closed_ = true
      current_reader_ = null
      current_writer_ = null
      reader_ = null

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
      while data := current_reader_.read:
        null  // Do nothing with the data.
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
  close_write:
    if not current_reader_:
      close
    else if socket_:
      socket_.close_write
      write_closed_ = true

  send_headers -> BodyWriter
      status/string headers/Headers
      --is_client_request/bool
      --has_body/bool:
    if current_writer_: throw "Previous request not completed"
    body_writer/BodyWriter := ?
    needs_to_write_chunked_header := false

    if has_body:
      content_length := headers.single "Content-Length"
      if content_length:
        length := int.parse content_length
        body_writer = ContentLengthWriter this writer_ length
      else:
        needs_to_write_chunked_header = true
        body_writer = ChunkedWriter this writer_
    else:
      // Return a writer that doesn't accept any data.
      body_writer = ContentLengthWriter this writer_ 0
      if not headers.matches "Connection" "upgrade":
        headers.set "Content-Length" "0"

    // Set this before doing blocking operations on the socket, so that we
    // don't let another task start another request on the same connection.
    current_writer_ = body_writer

    socket_.set_no_delay false

    writer_.write status
    headers.write_to writer_
    if is_client_request and host_:
      writer_.write "Host: $host_\r\n"
    if needs_to_write_chunked_header:
      writer_.write "Transfer-Encoding: chunked\r\n"
    writer_.write "\r\n"

    socket_.set_no_delay true
    return body_writer

  // Gets the next request from the client. If the client closes the
  // connection, returns null.
  read_request -> RequestIncoming?:
    // In theory HTTP/1.1 can support pipelining, but it causes issues
    // with many servers, so nobody uses it.
    if current_reader_: throw "Previous response not yet finished"
    if not socket_: return null

    if not reader_.can_ensure 1:
      if write_closed_: close
      return null
    index_of_first_space := reader_.index_of_or_throw ' '
    method := reader_.read_string (index_of_first_space)
    reader_.skip 1
    path := reader_.read_string (reader_.index_of_or_throw ' ')
    reader_.skip 1
    version := reader_.read_string (reader_.index_of_or_throw '\r')
    reader_.skip 1
    if reader_.read_byte != '\n': throw "FORMAT_ERROR"

    headers := read_headers_
    current_reader_ = body_reader_ headers --request=true

    body_reader := current_reader_ or ContentLengthReader this reader_ 0
    return RequestIncoming.private_ this body_reader method path version headers

  detach -> DetachedSocket_:
    if not socket_: throw "ALREADY_CLOSED"
    socket := socket_
    socket_ = null
    buffered := reader_.read_bytes reader_.buffered
    remove_finalizer this
    return DetachedSocket_ socket buffered

  read_response -> Response:
    if current_reader_: throw "Previous response not yet finished"
    headers := null
    try:
      version := reader_.read_string (reader_.index_of_or_throw ' ')
      reader_.skip 1
      status_code := int.parse (reader_.read_string (reader_.index_of_or_throw ' '))
      reader_.skip 1
      status_message := reader_.read_string (reader_.index_of_or_throw '\r')
      reader_.skip 1
      if reader_.read_byte != '\n': throw "FORMAT_ERROR"

      headers = read_headers_
      current_reader_ = body_reader_ headers --request=false --status_code=status_code

      body_reader := current_reader_ or ContentLengthReader this reader_ 0
      return Response this version status_code status_message headers body_reader

    finally:
      if not headers:
        close

  body_reader_ headers/Headers --request/bool --status_code/int?=null -> reader.Reader?:
    content_length := headers.single "Content-Length"
    if content_length:
      length := int.parse content_length
      if length == 0: return null  // No read is needed to drain this response.
      return ContentLengthReader this reader_ length

    // The only transfer encodings we support are 'identity' and 'chunked',
    // which are both required by HTTP/1.1.
    T_E ::= "Transfer-Encoding"
    if headers.single T_E:
      if headers.matches T_E "chunked":
        return ChunkedReader this reader_
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
    return UnknownContentLengthReader this reader_

  // Optional whitespace is spaces and tabs.
  is_whitespace_ char:
    return char == ' ' or char == '\t'

  read_headers_:
    headers := Headers

    while (reader_.byte 0) != '\r':

      if is_whitespace_ (reader_.byte 0):
        // Line folded headers are deprecated in RFC 7230 and we don't support
        // them.
        throw "FOLDED_HEADER"
      key := reader_.read_string (reader_.index_of ':')
      reader_.skip 1

      while is_whitespace_ (reader_.byte 0): reader_.skip 1

      value := reader_.read_string (reader_.index_of '\r')
      reader_.skip 1
      if reader_.read_byte != '\n': throw "FORMAT_ERROR"

      headers.add key value

    reader_.skip 1
    if reader_.read_byte != '\n': throw "FORMAT_ERROR"

    return headers

  reading_done_ reader:
    if current_reader_:
      if reader != current_reader_: throw "Read from reader that was already done"
      current_reader_ = null
      if write_closed_: close

  writing_done_ writer:
    if current_writer_:
      if writer != current_writer_: throw "Close of a writer that was already done"
      current_writer_ = null

class ContentLengthReader implements reader.SizedReader:
  connection_/Connection
  reader_/reader.BufferedReader
  remaining_length_/int := ?
  content_length/int

  constructor .connection_ .reader_ .content_length:
    remaining_length_ = content_length

  size -> int:
    return content_length

  read -> ByteArray?:
    if remaining_length_ <= 0:
      connection_.reading_done_ this
      return null
    data := reader_.read --max_size=remaining_length_
    if not data:
      connection_.close
      throw reader.UNEXPECTED_END_OF_READER_EXCEPTION
    remaining_length_ -= data.size
    return data

class UnknownContentLengthReader implements reader.Reader:
  connection_/Connection
  reader_/reader.BufferedReader

  constructor .connection_ .reader_:

  read -> ByteArray?:
    data := reader_.read
    if not data:
      connection_.close  // After an unknown content length the connection must close.
      return null
    return data

interface BodyWriter:
  write data
  is_done -> bool
  close

class ContentLengthWriter implements BodyWriter:
  connection_/Connection? := null
  writer_/writer.Writer
  remaining_length_/int := ?

  constructor .connection_ .writer_ .remaining_length_:

  is_done -> bool:
    return remaining_length_ == 0

  write data:
    writer_.write data
    remaining_length_ -= data.size

  close:
    if connection_:
      connection_.writing_done_ this
    connection_ = null

/**
A $tcp.Socket doesn't support ungetting data that was already read for it, so we
  have this shim that will first return the data that was read before switching
  protocols.  Other functions are just passed through.
*/
class DetachedSocket_ implements tcp.Socket:
  socket_/tcp.Socket
  buffered_/ByteArray? := null

  // TODO(kasper): For now, it is necessary to keep track
  // of whether or not the TCP_NODELAY option has been enabled.
  // This will go away with an upgraded Toit SDK where the
  // underlying tcp.Socket support the $no_delay getter.
  no_delay_/bool? := null

  constructor .socket_ buffered_:

  // TODO(kasper): Remove this. Here for backwards compatibility.
  set_no_delay enabled/bool: socket_.set_no_delay enabled

  no_delay -> bool:
    if no_delay_ == null:
      set_no_delay false
      no_delay_ = false
    return no_delay_

  no_delay= value/bool -> none:
    set_no_delay value
    no_delay_ = value

  read -> ByteArray?:
    if result := buffered_:
      buffered_ = null
      if result.size > 0:
        return result
    return socket_.read

  write data from=0 to=data.size: return socket_.write data from to
  close_write: return socket_.close_write
  close: return socket_.close
  local_address -> net.SocketAddress: return socket_.local_address
  peer_address -> net.SocketAddress: return socket_.peer_address
  mtu -> int: return socket_.mtu

is_close_exception_ exception -> bool:
  return exception == reader.UNEXPECTED_END_OF_READER_EXCEPTION
      or exception == "Broken pipe"
      or exception == "Connection reset by peer"
      or exception == "NOT_CONNECTED"
      or (exception is string and exception.contains "connection was aborted")
      or (exception is string and exception.contains "connection was forcibly closed")
