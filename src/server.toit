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
  semaphore_/monitor.Semaphore? ::= null

  // For testing.
  call_in_finalizer_/Lambda? := null

  constructor --.read_timeout=DEFAULT_READ_TIMEOUT --max_tasks/int=1 --logger=log.default:
    logger_ = logger
    if max_tasks > 1: semaphore_ = monitor.Semaphore --count=max_tasks

  constructor.tls
      --.read_timeout=DEFAULT_READ_TIMEOUT
      --max_tasks/int=1
      --logger=log.default
      --certificate/tls.Certificate
      --root_certificates/List=[]:
    logger_ = logger
    use_tls_ = true
    certificate_ = certificate
    root_certificates_ = root_certificates
    if max_tasks > 1: semaphore_ = monitor.Semaphore --count=max_tasks

  listen interface/tcp.Interface port/int handler/Lambda -> none:
    server_socket := interface.tcp_listen port
    listen server_socket handler

  listen server_socket/tcp.ServerSocket handler/Lambda -> none:
    while true:
      parent_task_semaphore := null
      if semaphore_:
        parent_task_semaphore = semaphore_
        // Down the semaphore before the accept, so we just don't accept
        // connections if we are at the limit.
        semaphore_.down
      try:  // A try to ensure the semaphore is upped.
        accepted := server_socket.accept
        if not accepted: continue

        socket := accepted
        if use_tls_:
          socket = tls.Socket.server socket
            --certificate=certificate_
            --root_certificates=root_certificates_

        connection := Connection --location=null socket
        address := socket.peer_address
        logger := logger_.with_tag "peer" address
        logger.debug "client connected"

        // This code can be run in the current task or in a child task.
        handle_connection_closure := ::
          try:  // A try to ensure the semaphore is upped in the child task.
            detached := false
            e := catch --trace=(: not is_close_exception_ it and it != "DEADLINE_EXCEEDED_ERROR"):
              detached = run_connection_ connection handler logger
            connection.close_write
            close_logger := e ? logger.with_tag "reason" e : logger
            if detached:
              close_logger.debug "client socket detached"
            else:
              close_logger.debug "connection ended"
          finally:
            if semaphore_: semaphore_.up  // Up the semaphore when the task ends.
        // End of code that can be run in the current task or in a child task.

        parent_task_semaphore = null  // We got this far, the semaphore is ours.
        if semaphore_:
          task --background handle_connection_closure
        else:
          // For the single-task case, just run the connection in the current task.
          handle_connection_closure.call
      finally:
        // Up the semaphore if we threw before starting the task.
        if parent_task_semaphore: parent_task_semaphore.up

  web_socket request/RequestIncoming response_writer/ResponseWriter -> WebSocket?:
    nonce := WebSocket.check_server_upgrade_request_ request response_writer
    if nonce == null: return null
    response_writer.write_headers STATUS_SWITCHING_PROTOCOLS
    return WebSocket response_writer.detach --no-client

  run_connection_ connection/Connection handler/Lambda logger/log.Logger -> bool:
    if call_in_finalizer_: connection.call_in_finalizer_ = call_in_finalizer_
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
      finally: | is_exception exception |
        // Drain unread content to allow the connection to be reused.
        if writer.detached_: return true
        if is_exception:
          writer.close_on_exception_ "Internal Server error - $exception.value.stringify"
        else:
          request.drain
          writer.close

class ResponseWriter:
  static VERSION ::= "HTTP/1.1"

  connection_/Connection? := null
  request_/RequestIncoming
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

  close_on_exception_ message/string -> none:
    if body_writer_:
      // We already sent a good response code, but then something went
      // wrong.  Hard close (RST) the connection to signal to the other end
      // that we failed.
      connection_.close
      connection_ = null
    else:
      // We don't have a body writer, so perhaps we didn't send a response
      // yet.  Send a 500 to indicate an internal server error.
      write_headers_ STATUS_INTERNAL_SERVER_ERROR --message=message --has_body=false
    logger_.info message

  close:
    if body_writer_:
      if not body_writer_.is_done:
        // This is typically the case if the user's code set a Content-Length
        // header, but then didn't write enough data.
        close_on_exception_ "Not enough data produced by server"
    else:
      assert: not has_data_
      // Nothing was written, yet we are already closing.  This indicates
      // that something went wrong in the user's code.
      // We return a 500 error code and log the issue.
      write_headers_ STATUS_INTERNAL_SERVER_ERROR --message=null --has_body=false
      logger_.info "Returned from router without any data for the client"
    body_writer_.close

  detach -> tcp.Socket:
    detached_ = true
    connection := connection_
    connection_ = null
    return connection.detach
