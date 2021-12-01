import net
import net.tcp
import bytes
import monitor
import log
import writer

import .status_codes
import .headers
import .request
import .response
import .connection
import .chunked

class Server:
  static DEFAULT_READ_TIMEOUT/Duration ::= Duration --s=30

  interface_/tcp.Interface
  read_timeout/Duration
  logger_/log.Logger

  constructor .interface_ --.read_timeout=DEFAULT_READ_TIMEOUT --logger=log.default:
    logger_ = logger

  listen port/int handler/Lambda:
    server_socket := interface_.tcp_listen port
    while true:
      socket := server_socket.accept
      if not socket: continue

      task --background::
        connection := Connection socket
        try:
          address := socket.peer_address
          logger := logger_.with_tag "peer" address
          logger.debug "client connected"
          catch --trace=(: it != DEADLINE_EXCEEDED_ERROR):
            run_connection_ connection handler logger
          logger.debug "client disconnected"
        finally:
          socket.close

  run_connection_ connection/Connection handler/Lambda logger/log.Logger:
    while true:
      request := null
      with_timeout read_timeout:
        request = connection.read_request
      if not request: return
      request_logger := logger.with_tag "path" request.path
      request_logger.debug "incoming request"
      writer ::= ResponseWriter_ connection request_logger
      handler.call request writer
      // Drain unread content to get allow the connection to be reused.
      request.drain
      writer.close

class ResponseWriter_ implements ResponseWriter:
  static VERSION ::= "HTTP/1.1"

  connection_/Connection
  logger_/log.Logger
  headers_/Headers
  body_writer_/BodyWriter? := null

  constructor .connection_ .logger_:
    headers_ = Headers

  headers -> Headers:
    if body_writer_: throw "headers already written"
    return headers_

  write_headers status_code/int:

  write data:
    write_headers_ STATUS_OK
    body_writer_.write data

  write_headers_ status_code/int:
    if body_writer_: return
    body_writer_ = connection_.send_headers
      "$VERSION $status_code $(status_message status_code)\r\n"
      headers

  close:
    body_writer_.close
    //   logger_.warn "partial response" --tags={
    //     "remaining_length": remaining_length_,
    //   }

interface ResponseWriter:
  headers -> Headers
  write_headers status_code/int
  write data
