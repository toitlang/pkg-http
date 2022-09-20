// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader
import writer
import net
import net.tcp

import .request
import .response
import .chunked
import .headers

class Connection:
  socket_/tcp.Socket
  host_/string?
  reader_ := ?
  writer_/writer.Writer
  auto_close_/bool

  constructor .socket_ --host/string?=null --auto_close=false:
    auto_close_ = auto_close
    host_ = host
    reader_ = reader.BufferedReader socket_
    writer_ = writer.Writer socket_

  new_request method/string path/string headers/Headers -> Request:
    return Request.client this method path headers

  close:
    return socket_.close

  send_headers -> BodyWriter
      status/string headers/Headers
      --is_client_request/bool
      --has_body/bool:
    body_writer/BodyWriter := ?
    needs_to_write_chunked_header := false

    if has_body and not headers.matches "Connection" "Upgrade":
      content_length := headers.single "Content-Length"
      if content_length:
        length := int.parse content_length
        body_writer = ContentLengthWriter this writer_ length
      else:
        needs_to_write_chunked_header = true
        body_writer = ChunkedWriter writer_
    else:
      // Return a writer that doesn't accept any data.
      body_writer = ContentLengthWriter this writer_ 0

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
  read_request -> Request?:
    if not reader_.can_ensure 1: return null
    index_of_first_space := reader_.index_of_or_throw ' '
    method := reader_.read_string (index_of_first_space)
    reader_.skip 1
    path := reader_.read_string (reader_.index_of_or_throw ' ')
    reader_.skip 1
    version := reader_.read_string (reader_.index_of_or_throw '\r')
    reader_.skip 1
    if reader_.read_byte != '\n': throw "FORMAT_ERROR"

    headers := read_headers_
    reader := body_reader_ headers

    return Request.server this reader method path version headers

  read_response -> Response:
    version := reader_.read_string (reader_.index_of_or_throw ' ')
    reader_.skip 1
    status_code := int.parse (reader_.read_string (reader_.index_of_or_throw ' '))
    reader_.skip 1
    status_message := reader_.read_string (reader_.index_of_or_throw '\r')
    reader_.skip 1
    if reader_.read_byte != '\n': throw "FORMAT_ERROR"

    headers := read_headers_
    body := body_reader_ headers

    return Response this version status_code status_message headers body

  body_reader_ headers/Headers -> reader.Reader:
    if headers.matches "Connection" "upgrade":
      // If connection was upgraded, we don't know the encoding. Use a pure
      // pass-through reader.
      return reader_

    content_length := headers.single "Content-Length"
    if content_length:
      length := int.parse content_length
      return ContentLengthReader this reader_ length

    // The only transfer encodings we support are 'identity' and 'chunked',
    // which are both required by HTTP/1.1.
    TE := "Transfer-Encoding"
    if headers.single TE:
      if headers.starts_with TE "chunked":
        return ChunkedReader this reader_
      else if not headers.matches TE "identity":
        throw "No support for $TE: $(headers.single TE)"

    return ContentLengthReader this reader_ 0

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

  response_done_:
    if auto_close_: close

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
      connection_.response_done_
      return null
    data := reader_.read --max_size=remaining_length_
    if not data: throw reader.UNEXPECTED_END_OF_READER_EXCEPTION
    remaining_length_ -= data.size
    return data

interface BodyWriter:
  write data
  close

class ContentLengthWriter implements BodyWriter:
  connection_/Connection
  writer_/writer.Writer
  remaining_length_/int := ?

  constructor .connection_ .writer_ .remaining_length_:

  write data:
    writer_.write data
    remaining_length_ -= data.size

  close:
    if remaining_length_ != 0:
      connection_.socket_.close_write

class DetachedSocket_ implements tcp.Socket:
  socket_/tcp.Socket
  reader_/reader.Reader?

  // TODO(kasper): For now, it is necessary to keep track
  // of whether or not the TCP_NODELAY option has been enabled.
  // This will go away with an upgraded Toit SDK where the
  // underlying tcp.Socket support the $no_delay getter.
  no_delay_/bool? := null

  constructor .socket_ .reader_:

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

  read -> ByteArray?: return reader_.read
  write data from=0 to=data.size: return socket_.write data from to
  close_write: return socket_.close_write
  close: return socket_.close
  local_address -> net.SocketAddress: return socket_.local_address
  peer_address -> net.SocketAddress: return socket_.peer_address
  mtu -> int: return socket_.mtu
