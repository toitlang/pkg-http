// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import reader
import writer
import net.tcp

import .request
import .response
import .chunked
import .headers

class Connection:
  socket_/tcp.Socket
  host/string?
  reader_ := ?
  writer_/writer.Writer
  auto_close_/bool

  constructor .socket_ --.host/string?=null --auto_close=false:
    auto_close_ = auto_close
    reader_ = reader.BufferedReader socket_
    writer_ = writer.Writer socket_

  // reader:
  //   result := reader_
  //   reader_ = null
  //   return result

  new_request method url -> Request:
    return Request.client this method url

  close:
    return socket_.close

  send_headers status/string headers/Headers -> BodyWriter:
    body_writer := null
    content_length := headers.single "Content-Length"
    if content_length:
      length := int.parse content_length
      body_writer = ContentLengthWriter this writer_ length
    else:
      headers.add "Transfer-Encoding" "chunked"
      body_writer = ChunkedWriter writer_

    socket_.set_no_delay false

    writer_.write status
    headers.write_to writer_
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

  read_response:
    version := reader_.read_string (reader_.index_of_or_throw ' ')
    reader_.skip 1
    status_code := int.parse (reader_.read_string (reader_.index_of_or_throw ' '))
    reader_.skip 1
    status_message := reader_.read_string (reader_.index_of_or_throw '\r')
    reader_.skip 1
    if reader_.read_byte != '\n': throw "FORMAT_ERROR"

    headers := read_headers_
    reader := body_reader_ headers

    return Response.client this reader version status_code status_message headers

  body_reader_ headers/Headers -> reader.Reader:
    content_length := headers.single("Content-Length")
    if content_length:
      length := int.parse content_length
      return ContentLengthReader reader_ length

    // The only transfer encodings we support are 'identity' and 'chunked',
    // which are both required by HTTP/1.1.
    TE := "Transfer-Encoding"
    if headers.single TE:
      if headers.starts_with TE "chunked":
        return ChunkedReader reader_
      else if not headers.matches TE "identity":
        throw "No support for $TE: $(headers.single TE)"

    return ContentLengthReader reader_ 0

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

class ContentLengthReader implements reader.Reader:
  reader_/reader.BufferedReader
  remaining_length_/int := ?
  content_length/int

  constructor .reader_ .content_length:
    remaining_length_ = content_length

  read -> ByteArray?:
    if remaining_length_ <= 0: return null
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
