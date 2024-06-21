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
  port := start-server network
  run-client network port

run-client network port/int -> none:
  client := http.Client network

  web-socket := client.web-socket --host="localhost" --port=port

  task --background:: client-reading web-socket

  client-sending web-socket
  sleep --ms=200

client-sending web-socket -> none:
  web-socket.send "Hello, World!"
  web-socket.send "Hello, World!"
  web-socket.send "Hello, World!"
  writer := web-socket.start-sending
  writer.write "Hello, World!"
  writer.write "Now is the time for all good men"
  writer.write "to come to the aid of the party."
  writer.close
  web-socket.send #[3, 4, 5]

client-reading web-socket -> none:
  // Each message can come with its own reader, which can be
  // useful if messages are large.
  while reader := web-socket.start-receiving:
    size := 0
    text := reader.is-text ? "" : null
    while ba := reader.read:
      if text: text += ba.to-string
      size += ba.size
    if text:
      print "Message received: '$text'"
    else:
      print "Message received: size $size."

start-server network -> int:
  server-socket := network.tcp-listen 0
  port := server-socket.local-address.port
  server := http.Server
  task --background::
    server.listen server-socket:: | request/http.RequestIncoming response-writer/http.ResponseWriter |
      if request.path == "/":
        web-socket := server.web-socket request response-writer
        // The server end of the web socket just echoes back what it gets.
        // Here we don't use a new reader for each message, but just get
        // the message with a single call to `receive`.
        while data := web-socket.receive:
          print "Got $data"
          web-socket.send data
      else:
        response-writer.write-headers http.STATUS-NOT-FOUND --message="Not Found"
  return port
