// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import bytes
import log
import monitor
import net
import net.tcp
import tls
import writer

import .chunked
import .connection
import .headers
import .request
import .status_codes
import .web_socket

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

        connection := Connection --location=null socket
        detached := false
        try:
          address := socket.peer_address
          logger := logger_.with_tag "peer" address
          logger.debug "client connected"
          e := catch --trace=(: not is_close_exception_ it and it != "DEADLINE_EXCEEDED_ERROR"):
            detached = run_connection_ connection handler logger
          close_logger := e ? logger.with_tag "reason" e : logger
          if detached:
            close_logger.debug "client socket detached"
          else:
            close_logger.debug "connection ended"
        finally:
          connection.close_write

  web_socket request/Request response_writer/ResponseWriter -> WebSocket?:
    nonce := WebSocket.check_server_upgrade_request_ request response_writer
    if nonce == null: return null
    response_writer.write_headers STATUS_SWITCHING_PROTOCOLS
    return WebSocket response_writer.detach

  run_connection_ connection/Connection handler/Lambda logger/log.Logger -> bool:
    while true:
      request := null
      with_timeout read_timeout:
        request = connection.read_request
      if not request: return false
      request_logger := logger.with_tag "path" request.path
      request_logger.debug "incoming request"
      writer ::= ResponseWriter connection request request_logger
      try:
        handler.call request writer
      finally:
        // Drain unread content to allow the connection to be reused.
        if writer.detached_: return true
        request.drain
        writer.close

class ResponseWriter:
  static VERSION ::= "HTTP/1.1"

  connection_/Connection? := null
  request_/Request
  logger_/log.Logger
  headers_/Headers
  body_writer_/BodyWriter? := null
  detached_/bool := false
  has_data_/bool := false

  constructor .connection_ .request_ .logger_:
    headers_ = Headers

  headers -> Headers:
    if body_writer_: throw "headers already written"
    return headers_

  write_headers status_code/int --message/string?=null:
    if body_writer_: throw "headers already written"
    write_headers_ status_code --message=message --has_body=true

  write data:
    if data.size > 0: has_data_ = true
    write_headers_ STATUS_OK --message=null --has_body=true
    body_writer_.write data

  write_headers_ status_code/int --message/string? --has_body/bool:
    if body_writer_: return
    body_writer_ = connection_.send_headers
        "$VERSION $status_code $(message or (status_message status_code))\r\n"
        headers
        --is_client_request=false
        --has_body=has_body

  redirect status_code/int location/string --message/string?=null --body/string?=null -> none:
    headers.set "Location" location
    if body and body.size > 0:
      write_headers_ status_code --message=message --has_body=true
      body_writer_.write body
    else:
      write_headers_ status_code --message=message --has_body=false

  close:
    if has_data_ or body_writer_:
      write_headers_ STATUS_OK --message=null --has_body=has_data_
    else:
      write_headers_ STATUS_INTERNAL_SERVER_ERROR --message=null --has_body=false
      logger_.info "Returned from router without any data for the client"
    body_writer_.close

  detach -> tcp.Socket:
    detached_ = true
    connection := connection_
    connection_ = null
    return connection.detach
