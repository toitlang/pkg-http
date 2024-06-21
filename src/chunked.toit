// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import io

import .connection

/**
This is an adapter that converts a chunked stream (RFC 2616) to a stream of
  just the payload bytes. It takes an $io.Reader as a constructor argument,
  and acts like an $io.Reader.

Deprecated for public use. Use the type $io.Reader instead.
This class will be made private in the future.
*/
class ChunkedReader extends ChunkedReader_:
  constructor connection/Connection reader/io.Reader:
    super connection reader

/**
This is an adapter that converts a chunked stream (RFC 2616) to a stream of
  just the payload bytes. It takes an $io.Reader as a constructor argument,
  and acts like an $io.Reader.
*/
class ChunkedReader_ extends io.Reader:
  connection_/Connection? := null
  reader_/io.Reader? := ?
  left-in-chunk_ := 0 // How much more raw data we are waiting for before the next size line.

  constructor .connection_ .reader_:

  /**
  Returns the underlying reader, which may have buffered up data.

  The ChunkedReader is unusable after a called to $detach-reader.

  Deprecated.
  */
  // TODO(florian): remove already now?
  detach-reader -> io.Reader:
    r := reader_
    reader_ = null
    return r

  read_ -> ByteArray?:
    while true:
      if not connection_:
        return null
      if left-in-chunk_ > 0:
        result := reader_.read --max-size=left-in-chunk_
        if not result: throw io.Reader.UNEXPECTED-END-OF-READER
        left-in-chunk_ -= result.size
        if left-in-chunk_ == 0:
          expect_ '\r'
          expect_ '\n'
        return result

      raw-length := reader_.read-bytes-up-to '\r'
      expect_ '\n'

      left-in-chunk_ = int.parse raw-length --radix=16

      // End is indicated by a zero hex length.
      if left-in-chunk_ == 0:
        expect_ '\r'
        expect_ '\n'
        connection_.reading-done_ this
        connection_ = null

  expect_ byte/int:
    b := reader_.peek-byte 0
    if b != byte: throw "PROTOCOL_ERROR"
    reader_.skip 1

/**
Deprecated for public use. Use the type $io.CloseableWriter instead.
This class will be made private in the future.
*/
class ChunkedWriter extends ChunkedWriter_:
  constructor connection/Connection writer/io.Writer:
      super connection writer

class ChunkedWriter_ extends io.CloseableWriter:
  static CRLF_ ::= "\r\n"

  connection_/Connection? := null
  writer_/io.Writer

  constructor .connection_ .writer_:

  // We don't know the amount of data ahead of time, so it may already be done.
  is-done_ -> bool:
    return true

  try-write_ data/io.Data from/int to/int -> int:
    size := to - from
    if size == 0: return 0
    write-header_ size
    writer_.write data from to  // Always writes all data.
    // Once we've sent the data, the other side might conclude that
    // they have gotten everything they need, so we don't want to throw
    // an exception on writing the final CRLF.
    catch: writer_.write CRLF_
    return size

  close_ -> none:
    if not connection_: return
    // Once we've sent the last chunk, the remaining transmitted information
    // is redundant, so we don't want to throw exceptions if the other side
    // closes the connection at this point.
    catch:
      writer_.write "0"
      writer_.write CRLF_
      writer_.write CRLF_
    connection_.writing-done_ this
    connection_ = null

  write-header_ length/int:
    writer_.write
      length.stringify 16
    writer_.write CRLF_
