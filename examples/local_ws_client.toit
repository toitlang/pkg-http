// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import net

// Connect to a test server on localhost.
// Eg. made with https://pypi.org/project/simple-websocket-server/
// The server is expected to just echo back the packets it gets.

main:
  network := net.open
  client := http.Client network

  websocket := client.web_socket "localhost:8000" "/"

  task --background::
    print "Message received: '$websocket.receive'"
    while reader := websocket.start_receiving:
      size := 0
      text := reader.is_text ? "" : null
      while ba := reader.read:
        if text: text += ba.to_string
        size += ba.size
      if text:
        print "Message received: '$text'"
      else:
        print "Message received: size $size."

  websocket.send "Hello, World!"
  websocket.send "Hello, World!"
  websocket.send "Hello, World!"
  writer := websocket.start_sending
  writer.write "Hello, World!"
  writer.write "Now is the time for all good men"
  writer.write "to come to the aid of the party."
  writer.close
  websocket.send #[3, 4, 5]
  sleep --ms=200
