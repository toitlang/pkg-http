// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import net

/**
Example that demonstrates a web-socket client and server.
The server simply echos back any incoming message.
*/

main:
  network := net.open
  port := start_server network
  run_client network port

run_client network port/int -> none:
  client := http.Client network

  web_socket := client.web_socket --host="localhost" --port=port

  task --background:: client_reading web_socket

  client_sending web_socket
  sleep --ms=200

client_sending web_socket -> none:
  web_socket.send "Hello, World!"
  web_socket.send "Hello, World!"
  web_socket.send "Hello, World!"
  writer := web_socket.start_sending
  writer.write "Hello, World!"
  writer.write "Now is the time for all good men"
  writer.write "to come to the aid of the party."
  writer.close
  web_socket.send #[3, 4, 5]

client_reading web_socket -> none:
  // Each message can come with its own reader, which can be
  // useful if messages are large.
  while reader := web_socket.start_receiving:
    size := 0
    text := reader.is_text ? "" : null
    while ba := reader.read:
      if text: text += ba.to_string
      size += ba.size
    if text:
      print "Message received: '$text'"
    else:
      print "Message received: size $size."

start_server network -> int:
  server_socket := network.tcp_listen 0
  port := server_socket.local_address.port
  server := http.Server
  task --background::
    server.listen server_socket:: | request/http.RequestIncoming response_writer/http.ResponseWriter |
      if request.path == "/":
        web_socket := server.web_socket request response_writer
        // The server end of the web socket just echoes back what it gets.
        // Here we don't use a new reader for each message, but just get
        // the message with a single call to `receive`.
        while data := web_socket.receive:
          print "Got $data"
          web_socket.send data
      else:
        response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
  return port
