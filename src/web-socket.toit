// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import bitmap show blit XOR
import crypto.sha1 show sha1
import encoding.base64
import io
import io show BIG-ENDIAN
import monitor show Semaphore
import net.tcp

import .headers
import .request
import .response
import .client show Client
import .server
import .status-codes

OPCODE-CONTINUATION_ ::= 0
OPCODE-TEXT_         ::= 1
OPCODE-BINARY_       ::= 2
OPCODE-CLOSE_        ::= 8
OPCODE-PING_         ::= 9
OPCODE-PONG_         ::= 10
FIN-FLAG_            ::= 0x80
EIGHT-BYTE-SIZE_     ::= 127
TWO-BYTE-SIZE_       ::= 126
MAX-ONE-BYTE-SIZE_   ::= 125
MASKING-FLAG_        ::= 0x80

/**
A WebSocket connection.
A bidirectional socket connection capable of sending binary or text messages
  according to RFC 6455.
Obtained from the $Client.web-socket or the $Server.web-socket methods.
Currently does not implement ping and pong packets.
*/
class WebSocket:
  socket_ /tcp.Socket
  current-writer_ /WebSocketWriter? := null
  writer-semaphore_ := Semaphore --count=1
  current-reader_ /WebSocketReader? := null
  is-client_ /bool

  constructor .socket_ --client/bool:
    is-client_ = client

  read_ -> ByteArray?:
    return socket_.in.read

  unread_ byte-array/ByteArray -> none:
    socket_.in.unget byte-array

  /**
  Reads a whole message, returning it as a string or a ByteArray.
  Returns null if the connection is closed.
  Messages transmitted as text are returned as strings.
  Messages transmitted as binary are returned as byte arrays.
  For connections with potentially large messages, consider using
    $start-receiving instead to stream the data.
  With $force-byte-array returns a byte array even if the
    peer marks the message as text.  This can be useful to avoid
    exceptions if the peer is marking invalid UTF-8 messages as
    text.
  */
  receive --force-byte-array=false -> any?:
    reader := start-receiving
    if reader == null: return null
    list := []
    while chunk := reader.read:
      list.add chunk
    text := reader.is-text and not force-byte-array
    if list.size == 0: return text ? "" : #[]
    if list.size == 1: return text ? list[0].to-string : list[0]
    size := list.reduce --initial=0: | sz byte-array | sz + byte-array.size
    result := ByteArray size
    position := 0
    list.do:
      result.replace position it
      position += it.size
    list = []  // Free up some memory before the big to_string.
    return text ? result.to-string : result

  /**
  Returns a reader for the next message sent to us on the WebSocket.
  Returns null if the connection is closed.
  Should not be called until the previous reader has been fully read.
  See also $receive if you know messages are small enough to fit in memory.
  */
  start-receiving -> WebSocketReader?:
    if current-reader_ != null:
      close --status-code=STATUS-WEBSOCKET-UNEXPECTED-CONDITION
      throw "PREVIOUS_READER_NOT_FINISHED"
    fragment-reader := null
    while not fragment-reader:
      fragment-reader = next-fragment_
      if fragment-reader == null or fragment-reader.is-close :
        return null
      fragment-reader = handle-any-ping_ fragment-reader
    if fragment-reader.is-continuation:
      close --status-code=STATUS-WEBSOCKET-PROTOCOL-ERROR
      throw "PROTOCOL_ERROR"
    size := fragment-reader.size_
    current-reader_ = WebSocketReader.private_ this fragment-reader fragment-reader.is-text fragment-reader.size
    return current-reader_

  handle-any-ping_ next-fragment/FragmentReader_ -> FragmentReader_?:
    if next-fragment.is-pong:
      while next-fragment.read:
        null  // Drain the pong.
      return null  // Nothing to do in response to a pong.
    if next-fragment.is-ping:
      payload := #[]
      while packet := next-fragment.read:
        payload += packet
      schedule-ping_ payload OPCODE-PONG_
      return null
    return next-fragment

  // Reads the header of the next fragment.
  next-fragment_ -> FragmentReader_?:
    if socket_ == null: return null  // Closed.

    reader := socket_.in
    if not reader.try-ensure-buffered 1: return null

    control-bits := reader.read-byte
    masking-length-byte := reader.read-byte
    masking := (masking-length-byte & MASKING-FLAG_) != 0
    len := masking-length-byte & 0x7f

    if len == TWO-BYTE-SIZE_:
      len = reader.big-endian.read-uint16 // BIG_ENDIAN.uint16 pending_ 2
    else if len == EIGHT-BYTE-SIZE_:
      len = reader.big-endian.read-int64  // BIG_ENDIAN.int64 pending_ 2

    masking-bytes := null
    if masking:
      masking-bytes = reader.read-bytes 4
      if masking-bytes == #[0, 0, 0, 0]:
        masking-bytes = null
    result := FragmentReader_ this len control-bits --masking-bytes=masking-bytes
    if not result.is-ok_:
      close --status-code=STATUS-WEBSOCKET-PROTOCOL-ERROR
      throw "PROTOCOL_ERROR"

    if result.is-close:
      if result.size >= 2:
        // Two-byte close reason code.
        payload := #[]
        while packet := result.read:
          payload += packet
        code := BIG-ENDIAN.uint16 payload 0
        if code == STATUS-WEBSOCKET-NORMAL-CLOSURE or code == STATUS-WEBSOCKET-GOING-AWAY:
          // One of the expected no-error codes.
          current-reader_ = null
          return null
        throw "Peer closed with code $code"
      // No code provided.  We treat this as a normal close.
      current-reader_ = null
      return null

    return result

  /**
  Sends a ByteArray or string as a framed WebSockets message.
  Strings are sent as text, whereas all other data objects are sent as binary.
  The message is sent as one large fragment, which means we cannot
    send pings and pongs until it is done.
  Calls to this method will block until the previous message has been
    completely sent.
  */
  send data/io.Data -> none:
    writer := start-sending --size=data.byte-size --opcode=((data is string) ? OPCODE-TEXT_ : OPCODE-BINARY_)
    writer.write data
    writer.close

  /**
  Starts sending a message to the peer.
  If the size is given, the message is sent as a single fragment so that
    the receiver knows the size.  In theory, proxies could split the fragment
    into multiple fragments, which would ruin this.  In practice this seems
    rare, and with TLS it is almost impossible.
  The fragment size is at the WebSockets level and has no connection with
    the size of IP packets or TLS buffers.
  The message is sent as a text message if the first data written to the
    writer is a string, otherwise as a binary message.
  Returns a writer, which must be completed (all data sent, and closed) before
    another message can be sent.  Calls to $send and $start-sending will
    block until the previous writer is completed.
  */
  start-sending --size/int?=null --opcode/int?=null -> io.CloseableWriter:
    writer-semaphore_.down
    assert: current-writer_ == null
    current-writer_ = WebSocketWriter.private_ this size --masking=is-client_ --opcode=opcode
    return current-writer_

  /**
  Send a ping with the given $payload, which is a string or a ByteArray.
  Any pongs we get back are ignored.
  If we are in the middle of sending a long message that was started with
    $start-sending then the ping may be interleaved with the fragments of the
    long message.
  */
  ping payload -> none:
    schedule-ping_ payload OPCODE-PING_

  schedule-ping_ payload opcode/int -> none:
    if current-writer_:
      current-writer_.pending-pings_.add [opcode, payload]
    else:
      writer-semaphore_.down
      try:
        // Send immediately.
        writer := WebSocketWriter.private_ this payload.size --masking=is-client_ --opcode=opcode
        writer.write payload
        writer.close
      finally:
        critical-do --no-respect-deadline:
          writer-semaphore_.up

  writer-close_ writer/WebSocketWriter -> none:
    current-writer_ = null
    writer-semaphore_.up

  write_ data/io.Data from=0 to=data.byte-size -> none:
    socket_.out.write data from to

  reader-close_ -> none:
    current-reader_ = null

  /**
  Closes the websocket.
  Call this if we do not wish to send or receive any more messages.
    After calling this, you do not need to call $close-write.
  May close abruptly in an unclean way.
  If we are in a suitable place in the protocol, sends a close packet first.
  */
  close --status-code/int=STATUS-WEBSOCKET-NORMAL-CLOSURE:
    close-write --status-code=status-code
    socket_.close
    current-reader_ = null

  /**
  Closes the websocket for writing.
  Call this if we are done transmitting messages, but we may have a different
    task still receiving messages on the connection.
  If we are in a suitable place in the protocol, sends a close packet first.
    Otherwise, it will close abruptly, without sending the packet.
  Most peers will respond by closing the other direction.
  */
  close-write --status-code/int=STATUS-WEBSOCKET-NORMAL-CLOSURE:
    if current-writer_ == null:
      writer-semaphore_.down
      try:
        // If we are not in the middle of a message, we can send a close packet.
        catch:  // Catch because the write end may already be closed.
          writer := WebSocketWriter.private_ this 2 --masking=is-client_ --opcode=OPCODE-CLOSE_
          payload := ByteArray 2
          BIG-ENDIAN.put-uint16 payload 0 status-code
          writer.write payload
          writer.close
      finally:
        critical-do --no-respect-deadline:
          writer-semaphore_.up
    socket_.out.close
    if current-writer_:
      current-writer_ = null
      writer-semaphore_.up

  static add-client-upgrade-headers_ headers/Headers -> string:
    // The WebSocket nonce is not very important and does not need to be
    // cryptographically random.
    nonce := base64.encode (ByteArray 16: random 0x100)
    headers.add "Upgrade" "websocket"
    headers.add "Sec-WebSocket-Key" nonce
    headers.add "Sec-WebSocket-Version" "13"
    headers.add "Connection" "Upgrade"
    return nonce

  static check-client-upgrade-response_ response/Response nonce/string -> none:
    if response.status-code != STATUS-SWITCHING-PROTOCOLS:
      throw "WebSocket upgrade failed with $response.status-code $response.status-message"
    upgrade-header := response.headers.single "Upgrade"
    connection-header := response.headers.single "Connection"
    if not upgrade-header
        or not connection-header
        or (Headers.ascii-normalize_ upgrade-header) != "Websocket"
        or (Headers.ascii-normalize_ connection-header) != "Upgrade"
        or (response.headers.single "Sec-WebSocket-Accept") != (WebSocket.response_ nonce):
      throw "MISSING_HEADER_IN_RESPONSE"
    if response.headers.single "Sec-WebSocket-Extensions"
        or response.headers.single "Sec-WebSocket-Protocol":
      throw "UNKNOWN_HEADER_IN_RESPONSE"

  /**
  Checks whether the request is a WebSocket upgrade request.
  If it is a valid upgrade request, adds the required headers to the response_writer
    and sends a response confirming the upgrade.
  Otherwise responds with an error code and returns null.
  */
  static check-server-upgrade-request_ request/RequestIncoming response-writer/ResponseWriter -> string?:
    connection-header := request.headers.single "Connection"
    upgrade-header := request.headers.single "Upgrade"
    version-header := request.headers.single "Sec-WebSocket-Version"
    nonce := request.headers.single "Sec-WebSocket-Key"
    message := null
    if nonce == null:                                                  message = "No nonce"
    else if nonce.size != 24:                                          message = "Bad nonce size"
    else if not connection-header or not upgrade-header:               message = "No upgrade headers"
    else if (Headers.ascii-normalize_ connection-header) != "Upgrade": message = "No Connection: Upgrade"
    else if (Headers.ascii-normalize_ upgrade-header) != "Websocket":  message = "No Upgrade: websocket"
    else if version-header != "13":                                    message = "Unrecognized Websocket version"
    else:
      response-writer.headers.add "Sec-WebSocket-Accept" (response_ nonce)
      response-writer.headers.add "Connection" "Upgrade"
      response-writer.headers.add "Upgrade" "websocket"
      return nonce
    response-writer.write-headers STATUS-BAD-REQUEST --message=message
    return null

  static response_ nonce/string -> string:
    expected-response := base64.encode
        sha1 nonce + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    return expected-response

/**
A writer for writing a single message on a WebSocket connection.
*/
class WebSocketWriter extends io.CloseableWriter:
  owner_ /WebSocket? := ?
  size_ /int?
  remaining-in-fragment_ /int := 0
  fragment-sent_ /bool := false
  masking_ /bool
  // Pings and pongs can be interleaved with the fragments in a message.
  pending-pings_ /List := []

  constructor.private_ .owner_ .size_ --masking/bool --opcode/int?=null:
    masking_ = masking
    if size_ and opcode:
      remaining-in-fragment_ = write-fragment-header_ size_ opcode size_

  try-write_ data/io.Data from/int to/int -> int:
    if owner_ == null: throw "ALREADY_CLOSED"
    total-size := to - from
    while from != to:
      // If no more can be written in the current fragment we need to write a
      // new fragment header.
      if remaining-in-fragment_ == 0:
        write-any-ping_  // Interleave pongs with message fragments.
        // Determine opcode for the new fragment.
        opcode := data is string ? OPCODE-TEXT_ : OPCODE-BINARY_
        if fragment-sent_:
          opcode = OPCODE-CONTINUATION_
        else:
          fragment-sent_ = true

        remaining-in-fragment_ = write-fragment-header_ (to - from) opcode size_

      while from < to and remaining-in-fragment_ != 0:
        size := min (to - from) remaining-in-fragment_
        // We don't use slices because data might be a string with UTF-8
        // sequences in it.
        owner_.write_ data from (from + size)
        from += size
        remaining-in-fragment_ -= size

    if remaining-in-fragment_ == 0: write-any-ping_

    return total-size

  write-any-ping_ -> none:
    while owner_ and pending-pings_.size != 0:
      assert: remaining-in-fragment_ == 0
      item := pending-pings_[0]
      pending-pings_ = pending-pings_.copy 1
      opcode := item[0]
      payload := item[1]
      write-fragment-header_ payload.size opcode payload.size
      owner_.write_ payload

  write-fragment-header_ max-size/int opcode/int size/int?:
    header /ByteArray := ?
    // If the protocol requires it, we supply a 4 byte mask, but it's always
    // zero so we don't need to apply it on send.
    masking-flag := masking_ ? MASKING-FLAG_ : 0
    remaining-in-fragment := ?
    if size:
      // We know the size.  Write a single fragment with the fin flag and the
      // exact size.
      if opcode == OPCODE-CONTINUATION_: throw "TOO_MUCH_WRITTEN"
      remaining-in-fragment = size
      if size > 0xffff:
        header = ByteArray (masking_ ? 14 : 10)
        header[1] = EIGHT-BYTE-SIZE_ | masking-flag
        BIG-ENDIAN.put-int64 header 2 size
      else if size > MAX-ONE-BYTE-SIZE_:
        header = ByteArray (masking_ ? 8 : 4)
        header[1] = TWO-BYTE-SIZE_ | masking-flag
        BIG-ENDIAN.put-uint16 header 2 size
      else:
        header = ByteArray (masking_ ? 6 : 2)
        header[1] = size | masking-flag
      header[0] = opcode | FIN-FLAG_
    else:
      // We don't know the size.  Write multiple fragments of up to
      // 125 bytes.
      remaining-in-fragment = min MAX-ONE-BYTE-SIZE_ max-size
      header = ByteArray (masking_ ? 6 : 2)
      header[0] = opcode
      header[1] = remaining-in-fragment | masking-flag

    owner_.write_ header

    return remaining-in-fragment

  close_:
    if remaining-in-fragment_ != 0: throw "TOO_LITTLE_WRITTEN"
    if owner_:
      if size_ == null:
        // If size is null, we didn't know the size of the complete message ahead
        // of time, which means we didn't set the fin flag on the last packet.  Send
        // a zero length packet with a fin flag.
        header := ByteArray 2
        header[0] = FIN-FLAG_ | (fragment-sent_ ? OPCODE-CONTINUATION_ : OPCODE-BINARY_)
        owner_.write_ header
      write-any-ping_
      owner_.writer-close_ this  // Notify the websocket that we are done.
      owner_ = null

/**
A reader for an individual message sent to us.
*/
class WebSocketReader extends io.Reader:
  owner_ /WebSocket? := ?
  is-text /bool
  fragment-reader_ /FragmentReader_ := ?

  /**
  The size of the incoming message if known.
  Null, otherwise.
  */
  size /int?

  constructor.private_ .owner_ .fragment-reader_ .is-text .size:

  /**
  Returns a byte array, or null if the message has been fully read.
  Note that even if the message is transmitted as text, it arrives as
    ByteArrays.
  */
  read_ -> ByteArray?:
    result := fragment-reader_.read
    if result == null:
      if fragment-reader_.is-fin:
        if owner_:
          owner_.reader-close_
          owner_ = null
          return null
      if owner_ == null: return null  // Closed.
      next-fragment := null
      while not next-fragment:
        next-fragment = owner_.next-fragment_
        if not next-fragment: return null  // Closed.
        next-fragment = owner_.handle-any-ping_ next-fragment
      fragment-reader_ = next-fragment
      if not fragment-reader_.is-continuation:
        throw "PROTOCOL_ERROR"
      result = fragment-reader_.read
    if fragment-reader_.is-fin and fragment-reader_.is-exhausted:
      if owner_:
        owner_.reader-close_
        owner_ = null
    return result

class FragmentReader_:
  owner_ /WebSocket
  control-bits_ /int
  size_ /int
  received_ := 0
  masking-bytes /ByteArray?

  constructor .owner_ .size_ .control-bits_ --.masking-bytes/ByteArray?=null:

  is-continuation -> bool: return control-bits_ & 0x0f == OPCODE-CONTINUATION_
  is-text -> bool:         return control-bits_ & 0x0f == OPCODE-TEXT_
  is-binary -> bool:       return control-bits_ & 0x0f == OPCODE-BINARY_
  is-close -> bool:        return control-bits_ & 0x0f == OPCODE-CLOSE_
  is-ping -> bool:         return control-bits_ & 0x0f == OPCODE-PING_
  is-pong -> bool:         return control-bits_ & 0x0f == OPCODE-PONG_
  is-fin -> bool:          return control-bits_ & FIN-FLAG_ != 0
  is-exhausted -> bool:    return received_ == size_

  is-ok_ -> bool:
    if control-bits_ & 0x70 != 0: return false
    opcode := control-bits_ & 0xf
    return opcode < 3 or 8 <= opcode <= 10

  read -> ByteArray?:
    if received_ == size_: return null
    next-byte-array := owner_.read_
    if next-byte-array == null: throw "CONNECTION_CLOSED"
    max := size_ - received_
    if next-byte-array.size > max:
      owner_.unread_ next-byte-array[max..]
      next-byte-array = next-byte-array[..max]
    if masking-bytes:
      unmask-bytes_ next-byte-array masking-bytes received_
    received_ += next-byte-array.size
    return next-byte-array

  size -> int?:
    if control-bits_ & FIN-FLAG_ == 0: return null
    return size_

  static unmask-bytes_ byte-array/ByteArray masking-bytes/ByteArray received/int -> none:
    for i := 0; i < byte-array.size; i++:
      if received & 3 == 0 and i + 4 < byte-array.size:
        // When we are at the start of the masking bytes we can accelerate with blit.
        blit
          masking-bytes           // Source.
          byte-array[i..]         // Destination.
          4                       // Line width of 4 bytes.
          --source-line-stride=0  // Restart at the beginning of the masking bytes on every line.
          --operation=XOR         // dest[i] ^= source[j].
        // Skip the bytes we just blitted.
        blitted := round-down (byte-array.size - i) 4
        i += blitted
      if i < byte-array.size:
        byte-array[i] ^= masking-bytes[received++ & 3]
