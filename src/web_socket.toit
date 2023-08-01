// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import binary show BIG_ENDIAN
import bitmap show blit XOR
import crypto.sha1 show sha1
import encoding.base64
import monitor show Semaphore
import net.tcp
import reader
import writer

import .headers
import .request
import .response
import .client show Client
import .server
import .status_codes

OPCODE_CONTINUATION_ ::= 0
OPCODE_TEXT_         ::= 1
OPCODE_BINARY_       ::= 2
OPCODE_CLOSE_        ::= 8
OPCODE_PING_         ::= 9
OPCODE_PONG_         ::= 10
FIN_FLAG_            ::= 0x80
EIGHT_BYTE_SIZE_     ::= 127
TWO_BYTE_SIZE_       ::= 126
MAX_ONE_BYTE_SIZE_   ::= 125
MASKING_FLAG_        ::= 0x80

/**
A WebSocket connection.
A bidirectional socket connection capable of sending binary or text messages
  according to RFC 6455.
Obtained from the $Client.web_socket or the $Server.web_socket methods.
Currently does not implement ping and pong packets.
*/
class WebSocket:
  socket_ /tcp.Socket
  pending_ /ByteArray := #[]
  current_writer_ /WebSocketWriter? := null
  writer_semaphore_ := Semaphore --count=1
  current_reader_ /WebSocketReader? := null
  is_client_ /bool

  constructor .socket_ --client/bool:
    is_client_ = client

  read_ -> ByteArray?:
    if pending_.size != 0:
      result := pending_
      pending_ = #[]
      return result
    return socket_.read

  unread_ byte_array/ByteArray -> none:
    assert: pending_.size == 0
    pending_ = byte_array

  /**
  Reads a whole message, returning it as a string or a ByteArray.
  Returns null if the connection is closed.
  Messages transmitted as text are returned as strings.
  Messages transmitted as binary are returned as byte arrays.
  For connections with potentially large messages, consider using
    $start_receiving instead to stream the data.
  With $force_byte_array returns a byte array even if the
    peer marks the message as text.  This can be useful to avoid
    exceptions if the peer is marking invalid UTF-8 messages as
    text.
  */
  receive --force_byte_array=false -> any?:
    reader := start_receiving
    if reader == null: return null
    list := []
    while chunk := reader.read:
      list.add chunk
    text := reader.is_text and not force_byte_array
    if list.size == 0: return text ? "" : #[]
    if list.size == 1: return text ? list[0].to_string : list[0]
    size := list.reduce --initial=0: | sz byte_array | sz + byte_array.size
    result := ByteArray size
    position := 0
    list.do:
      result.replace position it
      position += it.size
    list = []  // Free up some memory before the big to_string.
    return text ? result.to_string : result

  /**
  Returns a reader for the next message sent to us on the WebSocket.
  Returns null if the connection is closed.
  Should not be called until the previous reader has been fully read.
  See also $receive if you know messages are small enough to fit in memory.
  */
  start_receiving -> WebSocketReader?:
    if current_reader_ != null:
      close --status_code=STATUS_WEBSOCKET_UNEXPECTED_CONDITION
      throw "PREVIOUS_READER_NOT_FINISHED"
    fragment_reader := null
    while not fragment_reader:
      fragment_reader = next_fragment_
      if fragment_reader == null or fragment_reader.is_close :
        return null
      fragment_reader = handle_any_ping_ fragment_reader
    if fragment_reader.is_continuation:
      close --status_code=STATUS_WEBSOCKET_PROTOCOL_ERROR
      throw "PROTOCOL_ERROR"
    size := fragment_reader.size_
    current_reader_ = WebSocketReader.private_ this fragment_reader fragment_reader.is_text fragment_reader.size
    return current_reader_

  handle_any_ping_ next_fragment/FragmentReader_ -> FragmentReader_?:
    if next_fragment.is_pong:
      while next_fragment.read:
        null  // Drain the pong.
      return null  // Nothing to do in response to a pong.
    if next_fragment.is_ping:
      payload := #[]
      while packet := next_fragment.read:
        payload += packet
      schedule_ping_ payload OPCODE_PONG_
      return null
    return next_fragment

  // Reads the header of the next fragment.
  next_fragment_ -> FragmentReader_?:
    if socket_ == null: return null  // Closed.
    // Named block:
    get_more := :
      next := socket_.read
      if next == null:
        if pending_.size == 0: return null
        throw "CONNECTION_CLOSED"
      pending_ += next

    while pending_.size < 2: get_more.call

    masking := pending_[1] & MASKING_FLAG_ != 0
    len := pending_[1] & 0x7f
    header_size_needed := ?
    if len == TWO_BYTE_SIZE_:
      header_size_needed = masking ? 8 : 4
    else if len == EIGHT_BYTE_SIZE_:
      header_size_needed = masking ? 14 : 10
    else:
      header_size_needed = masking ? 6 : 2

    while pending_.size < header_size_needed: get_more.call

    if len == TWO_BYTE_SIZE_:
      len = BIG_ENDIAN.uint16 pending_ 2
    else if len == EIGHT_BYTE_SIZE_:
      len = BIG_ENDIAN.int64 pending_ 2

    masking_bytes := null
    if masking:
      masking_bytes = pending_.copy (header_size_needed - 4) header_size_needed
      if masking_bytes == #[0, 0, 0, 0]:
        masking_bytes = null
    result := FragmentReader_ this len pending_[0] --masking_bytes=masking_bytes
    if not result.is_ok_:
      close --status_code=STATUS_WEBSOCKET_PROTOCOL_ERROR
      throw "PROTOCOL_ERROR"

    pending_ = pending_[header_size_needed..]

    if result.is_close:
      if result.size >= 2:
        // Two-byte close reason code.
        payload := #[]
        while packet := result.read:
          payload += packet
        code := BIG_ENDIAN.uint16 payload 0
        if code == STATUS_WEBSOCKET_NORMAL_CLOSURE or code == STATUS_WEBSOCKET_GOING_AWAY:
          // One of the expected no-error codes.
          current_reader_ = null
          return null
        throw "Peer closed with code $code"
      // No code provided.  We treat this as a normal close.
      current_reader_ = null
      return null

    return result

  /**
  Sends a ByteArray or string as a framed WebSockets message.
  Strings are sent as text, whereas byte arrays are sent as binary.
  The message is sent as one large fragment, which means we cannot
    send pings and pongs until it is done.
  Calls to this method will block until the previous message has been
    completely sent.
  */
  send data -> none:
    writer := start_sending --size=data.size --opcode=((data is string) ? OPCODE_TEXT_ : OPCODE_BINARY_)
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
    another message can be sent.  Calls to $send and $start_sending will
    block until the previous writer is completed.
  */
  start_sending --size/int?=null --opcode/int?=null -> WebSocketWriter:
    writer_semaphore_.down
    assert: current_writer_ == null
    current_writer_ = WebSocketWriter.private_ this size --masking=is_client_ --opcode=opcode
    return current_writer_

  /**
  Send a ping with the given $payload, which is a string or a ByteArray.
  Any pongs we get back are ignored.
  If we are in the middle of sending a long message that was started with
    $start_sending then the ping may be interleaved with the fragments of the
    long message.
  */
  ping payload -> none:
    schedule_ping_ payload OPCODE_PING_

  schedule_ping_ payload opcode/int -> none:
    if current_writer_:
      current_writer_.pending_pings_.add [opcode, payload]
    else:
      writer_semaphore_.down
      try:
        // Send immediately.
        writer := WebSocketWriter.private_ this payload.size --masking=is_client_ --opcode=opcode
        writer.write payload
        writer.close
      finally:
        writer_semaphore_.up

  writer_close_ writer/WebSocketWriter -> none:
    current_writer_ = null
    writer_semaphore_.up

  write_ data from=0 to=data.size -> none:
    written := 0
    while from < to:
      from += socket_.write data from to

  reader_close_ -> none:
    current_reader_ = null

  /**
  Closes the websocket.
  Call this if we do not wish to send or receive any more messages.
    After calling this, you do not need to call $close_write.
  May close abruptly in an unclean way.
  If we are in a suitable place in the protocol, sends a close packet first.
  */
  close --status_code/int=STATUS_WEBSOCKET_NORMAL_CLOSURE:
    close_write --status_code=status_code
    socket_.close
    current_reader_ = null

  /**
  Closes the websocket for writing.
  Call this if we are done transmitting messages, but we may have a different
    task still receiving messages on the connection.
  If we are in a suitable place in the protocol, sends a close packet first.
    Otherwise, it will close abruptly, without sending the packet.
  Most peers will respond by closing the other direction.
  */
  close_write --status_code/int=STATUS_WEBSOCKET_NORMAL_CLOSURE:
    if current_writer_ == null:
      writer_semaphore_.down
      // If we are not in the middle of a message, we can send a close packet.
      catch:  // Catch because the write end may already be closed.
        writer := WebSocketWriter.private_ this 2 --masking=is_client_ --opcode=OPCODE_CLOSE_
        payload := ByteArray 2
        BIG_ENDIAN.put_uint16 payload 0 status_code
        writer.write payload
        writer.close
      writer_semaphore_.up
    catch: socket_.close_write  // Catch because we allow double close, and a previous close causes an exception here.
    if current_writer_:
      current_writer_ = null
      writer_semaphore_.up

  static add_client_upgrade_headers_ headers/Headers -> string:
    // The WebSocket nonce is not very important and does not need to be
    // cryptographically random.
    nonce := base64.encode (ByteArray 16: random 0x100)
    headers.add "Upgrade" "websocket"
    headers.add "Sec-WebSocket-Key" nonce
    headers.add "Sec-WebSocket-Version" "13"
    headers.add "Connection" "Upgrade"
    return nonce

  static check_client_upgrade_response_ response/Response nonce/string -> none:
    if response.status_code != STATUS_SWITCHING_PROTOCOLS:
      throw "WebSocket upgrade failed with $response.status_code $response.status_message"
    upgrade_header := response.headers.single "Upgrade"
    connection_header := response.headers.single "Connection"
    if not upgrade_header
        or not connection_header
        or (Headers.ascii_normalize_ upgrade_header) != "Websocket"
        or (Headers.ascii_normalize_ connection_header) != "Upgrade"
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
  static check_server_upgrade_request_ request/RequestIncoming response_writer/ResponseWriter -> string?:
    connection_header := request.headers.single "Connection"
    upgrade_header := request.headers.single "Upgrade"
    version_header := request.headers.single "Sec-WebSocket-Version"
    nonce := request.headers.single "Sec-WebSocket-Key"
    message := null
    if nonce == null:                                                  message = "No nonce"
    else if nonce.size != 24:                                          message = "Bad nonce size"
    else if not connection_header or not upgrade_header:               message = "No upgrade headers"
    else if (Headers.ascii_normalize_ connection_header) != "Upgrade": message = "No Connection: Upgrade"
    else if (Headers.ascii_normalize_ upgrade_header) != "Websocket":  message = "No Upgrade: websocket"
    else if version_header != "13":                                    message = "Unrecognized Websocket version"
    else:
      response_writer.headers.add "Sec-WebSocket-Accept" (response_ nonce)
      response_writer.headers.add "Connection" "Upgrade"
      response_writer.headers.add "Upgrade" "websocket"
      return nonce
    response_writer.write_headers STATUS_BAD_REQUEST --message=message
    return null

  static response_ nonce/string -> string:
    expected_response := base64.encode
        sha1 nonce + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    return expected_response

/**
A writer for writing a single message on a WebSocket connection.
*/
class WebSocketWriter:
  owner_ /WebSocket? := ?
  size_ /int?
  remaining_in_fragment_ /int := 0
  fragment_sent_ /bool := false
  masking_ /bool
  // Pings and pongs can be interleaved with the fragments in a message.
  pending_pings_ /List := []

  constructor.private_ .owner_ .size_ --masking/bool --opcode/int?=null:
    masking_ = masking
    if size_ and opcode:
      remaining_in_fragment_ = write_fragment_header_ size_ opcode size_

  write data from=0 to=data.size -> int:
    if owner_ == null: throw "ALREADY_CLOSED"
    total_size := to - from
    while from != to:
      // If no more can be written in the current fragment we need to write a
      // new fragment header.
      if remaining_in_fragment_ == 0:
        write_any_ping_  // Interleave pongs with message fragments.
        // Determine opcode for the new fragment.
        opcode := data is string ? OPCODE_TEXT_ : OPCODE_BINARY_
        if fragment_sent_:
          opcode = OPCODE_CONTINUATION_
        else:
          fragment_sent_ = true

        remaining_in_fragment_ = write_fragment_header_ (to - from) opcode size_

      while from < to and remaining_in_fragment_ != 0:
        size := min (to - from) remaining_in_fragment_
        // We don't use slices because data might be a string with UTF-8
        // sequences in it.
        owner_.write_ data from (from + size)
        from += size
        remaining_in_fragment_ -= size

    if remaining_in_fragment_ == 0: write_any_ping_

    return total_size

  write_any_ping_ -> none:
    while owner_ and pending_pings_.size != 0:
      assert: remaining_in_fragment_ == 0
      item := pending_pings_[0]
      pending_pings_ = pending_pings_.copy 1
      opcode := item[0]
      payload := item[1]
      write_fragment_header_ payload.size opcode payload.size
      owner_.write_ payload

  write_fragment_header_ max_size/int opcode/int size/int?:
    header /ByteArray := ?
    // If the protocol requires it, we supply a 4 byte mask, but it's always
    // zero so we don't need to apply it on send.
    masking_flag := masking_ ? MASKING_FLAG_ : 0
    remaining_in_fragment := ?
    if size:
      // We know the size.  Write a single fragment with the fin flag and the
      // exact size.
      if opcode == OPCODE_CONTINUATION_: throw "TOO_MUCH_WRITTEN"
      remaining_in_fragment = size
      if size > 0xffff:
        header = ByteArray (masking_ ? 14 : 10)
        header[1] = EIGHT_BYTE_SIZE_ | masking_flag
        BIG_ENDIAN.put_int64 header 2 size
      else if size > MAX_ONE_BYTE_SIZE_:
        header = ByteArray (masking_ ? 8 : 4)
        header[1] = TWO_BYTE_SIZE_ | masking_flag
        BIG_ENDIAN.put_uint16 header 2 size
      else:
        header = ByteArray (masking_ ? 6 : 2)
        header[1] = size | masking_flag
      header[0] = opcode | FIN_FLAG_
    else:
      // We don't know the size.  Write multiple fragments of up to
      // 125 bytes.
      remaining_in_fragment = min MAX_ONE_BYTE_SIZE_ max_size
      header = ByteArray (masking_ ? 6 : 2)
      header[0] = opcode
      header[1] = remaining_in_fragment | masking_flag

    owner_.write_ header

    return remaining_in_fragment

  close:
    if remaining_in_fragment_ != 0: throw "TOO_LITTLE_WRITTEN"
    if owner_:
      if size_ == null:
        // If size is null, we didn't know the size of the complete message ahead
        // of time, which means we didn't set the fin flag on the last packet.  Send
        // a zero length packet with a fin flag.
        header := ByteArray 2
        header[0] = FIN_FLAG_ | (fragment_sent_ ? OPCODE_CONTINUATION_ : OPCODE_BINARY_)
        owner_.write_ header
      write_any_ping_
      owner_.writer_close_ this  // Notify the websocket that we are done.
      owner_ = null

/**
A reader for an individual message sent to us.
*/
class WebSocketReader implements reader.Reader:
  owner_ /WebSocket? := ?
  is_text /bool
  fragment_reader_ /FragmentReader_ := ?

  /**
  If the size of the incoming message is known, then it is returned, otherwise
    null is returned.
  Since a normal size method cannot return null, the WebSocketReader does not
    implement $reader.SizedReader.
  */
  size /int?

  constructor.private_ .owner_ .fragment_reader_ .is_text .size:

  /**
  Returns a byte array, or null if the message has been fully read.
  Note that even if the message is transmitted as text, it arrives as
    ByteArrays.
  */
  read -> ByteArray?:
    result := fragment_reader_.read
    if result == null:
      if fragment_reader_.is_fin:
        if owner_:
          owner_.reader_close_
          owner_ = null
          return null
      if owner_ == null: return null  // Closed.
      next_fragment := null
      while not next_fragment:
        next_fragment = owner_.next_fragment_
        if not next_fragment: return null  // Closed.
        next_fragment = owner_.handle_any_ping_ next_fragment
      fragment_reader_ = next_fragment
      if not fragment_reader_.is_continuation:
        throw "PROTOCOL_ERROR"
      result = fragment_reader_.read
    if fragment_reader_.is_fin and fragment_reader_.is_exhausted:
      if owner_:
        owner_.reader_close_
        owner_ = null
    return result

class FragmentReader_:
  owner_ /WebSocket
  control_bits_ /int
  size_ /int
  received_ := 0
  masking_bytes /ByteArray?

  constructor .owner_ .size_ .control_bits_ --.masking_bytes/ByteArray?=null:

  is_continuation -> bool: return control_bits_ & 0x0f == OPCODE_CONTINUATION_
  is_text -> bool:         return control_bits_ & 0x0f == OPCODE_TEXT_
  is_binary -> bool:       return control_bits_ & 0x0f == OPCODE_BINARY_
  is_close -> bool:        return control_bits_ & 0x0f == OPCODE_CLOSE_
  is_ping -> bool:         return control_bits_ & 0x0f == OPCODE_PING_
  is_pong -> bool:         return control_bits_ & 0x0f == OPCODE_PONG_
  is_fin -> bool:          return control_bits_ & FIN_FLAG_ != 0
  is_exhausted -> bool:    return received_ == size_

  is_ok_ -> bool:
    if control_bits_ & 0x70 != 0: return false
    opcode := control_bits_ & 0xf
    return opcode < 3 or 8 <= opcode <= 10

  read -> ByteArray?:
    if received_ == size_: return null
    next_byte_array := owner_.read_
    if next_byte_array == null: throw "CONNECTION_CLOSED"
    max := size_ - received_
    if next_byte_array.size > max:
      owner_.unread_ next_byte_array[max..]
      next_byte_array = next_byte_array[..max]
    if masking_bytes:
      unmask_bytes_ next_byte_array masking_bytes received_
    received_ += next_byte_array.size
    return next_byte_array

  size -> int?:
    if control_bits_ & FIN_FLAG_ == 0: return null
    return size_

  static unmask_bytes_ byte_array/ByteArray masking_bytes/ByteArray received/int -> none:
    for i := 0; i < byte_array.size; i++:
      if received & 3 == 0 and i + 4 < byte_array.size:
        // When we are at the start of the masking bytes we can accelerate with blit.
        blit
          masking_bytes           // Source.
          byte_array[i..]         // Destination.
          4                       // Line width of 4 bytes.
          --source_line_stride=0  // Restart at the beginning of the masking bytes on every line.
          --operation=XOR         // dest[i] ^= source[j].
        // Skip the bytes we just blitted.
        blitted := round_down (byte_array.size - i) 4
        i += blitted
      if i < byte_array.size:
        byte_array[i] ^= masking_bytes[received++ & 3]
