// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import net
import net.tcp
import bytes
import monitor
import log
import writer
import tls

import .status_codes
import .headers
import .request
import .response
import .connection
import .chunked

class Server:
  static DEFAULT_READ_TIMEOUT/Duration ::= Duration --s=30

  read_timeout/Duration

  logger_/log.Logger
  use_tls_/bool ::= false
  certificate_/tls.Certificate? ::= null
  root_certificates_/List ::= []

  constructor --.read_timeout=DEFAULT_READ_TIMEOUT --logger=log.default:
    logger_ = logger

  constructor.tls
      --.read_timeout=DEFAULT_READ_TIMEOUT
      --logger=log.default
      --certificate/tls.Certificate
      --root_certificates/List=[]:
    logger_ = logger
    use_tls_ = true
    certificate_ = certificate
    root_certificates_ = root_certificates

  listen interface/tcp.Interface port/int handler/Lambda -> none:
    server_socket := interface.tcp_listen port
    listen server_socket handler

  listen server_socket/tcp.ServerSocket handler/Lambda -> none:
    while true:
      accepted := server_socket.accept
      if not accepted: continue

      task --background::
        socket := accepted
        if use_tls_:
          socket = tls.Socket.server socket
            --certificate=certificate_
            --root_certificates=root_certificates_

        connection := Connection socket
        try:
          address := socket.peer_address
          logger := logger_.with_tag "peer" address
          logger.debug "client connected"
          e := catch:
            run_connection_ connection handler logger
          close_logger := e ? logger.with_tag "reason" e : logger
          close_logger.debug "client disconnected"
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
      catch --trace=(: it != DEADLINE_EXCEEDED_ERROR):
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
    if body_writer_: throw "headers already written"
    write_headers_ status_code

  write data:
    write_headers_ STATUS_OK
    body_writer_.write data

  write_headers_ status_code/int:
    if body_writer_: return
    body_writer_ = connection_.send_headers
      "$VERSION $status_code $(status_message status_code)\r\n"
      headers

  close:
    write_headers_ STATUS_OK
    body_writer_.close

interface ResponseWriter:
  headers -> Headers
  write_headers status_code/int
  write data
