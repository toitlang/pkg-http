import reader
import writer

import .connection

// This is an adapter that converts a chunked stream (RFC 2616) to a stream of
// just the payload bytes. It takes a BufferedReader as a constructor argument,
// and acts like a Socket or TlsSocket, having one method, called read, which
// returns ByteArrays.  End of stream is indicated with a null return value
// from read.
class ChunkedReader implements reader.Reader:
  reader_/reader.BufferedReader? := ?
  left_in_chunk_ := 0 // How much more raw data we are waiting for before the next size line.
  done_ := false

  constructor .reader_:

  /**
  Returns the underlying reader, which may have buffered up data.

  The ChunkedReader is unusable after a called to $detach_reader.
  */
  detach_reader -> reader.BufferedReader:
    r := reader_
    reader_ = null
    return r

  read -> ByteArray?:
    while true:
      if done_: return null
      if left_in_chunk_ > 0:
        result := reader_.read --max_size=left_in_chunk_
        if not result: throw reader.UNEXPECTED_END_OF_READER_EXCEPTION
        left_in_chunk_ -= result.size
        if left_in_chunk_ == 0:
          expect_ '\r'
          expect_ '\n'
        return result

      raw_length := reader_.read_bytes_until '\r'
      expect_ '\n'

      left_in_chunk_ = int.parse raw_length --radix=16

      // End is indicated by a zero hex length.
      if left_in_chunk_ == 0:
        expect_ '\r'
        expect_ '\n'
        done_ = true

  expect_ byte/int:
    b := reader_.byte 0
    if b != byte: throw "PROTOCOL_ERROR"
    reader_.skip 1

class ChunkedWriter implements BodyWriter:
  static CRLF_ ::= "\r\n"

  writer_/writer.Writer

  constructor .writer_:

  write data -> int:
    if data.size == 0: return 0
    write_header_ data.size
    writer_.write data
    writer_.write CRLF_
    return data.size

  close:
    write_header_ 0
    writer_.write CRLF_

  write_header_ length/int:
    writer_.write
      length.stringify 16
    writer_.write CRLF_
