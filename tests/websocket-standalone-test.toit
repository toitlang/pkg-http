// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import net
import http.web-socket show FragmentReader_

// Sets up a web server that can switch to websocket mode on the "/" path.
// The server just sends back everything it gets.
// Sets up a client that sends files and expects to receive them back.

main:
  unmark-bytes-test
  client-server-test

client-server-test:
  network := net.open
  port := start-server network
  run-client network port

run-client network port/int -> none:
  client := http.Client network

  web-socket := client.web-socket --host="localhost" --port=port --path="/"

  task:: client-reading web-socket

  client-sending web-socket

  web-socket.close-write

TEST-PACKETS := [
    "Hello, World!",
    "*" * 125,
    (ByteArray 125: it),
    "*" * 126,
    (ByteArray 126: it),
    "*" * 127,
    (ByteArray 127: it),
    "*" * 128,
    (ByteArray 128: it),
    "*" * 1000,
    (ByteArray 1000: it & 0xff),
    "Now is the time for all good men to come to the aid of the party.",
    "æøåßé" * 30,
    "€€£" * 40,
]

sent-but-not-reflected := 0

client-sending web-socket -> none:
  TEST-PACKETS.do: | packet |
    2.repeat:
      // Send with a single call to `send`.
      sent-but-not-reflected++
      web-socket.send packet
      // Send with a writer.
      sent-but-not-reflected++
      writer := web-socket.start-sending
      pos := 0
      ping-sent := false
      print packet.size
      while pos < packet.size:
        pos += writer.write packet pos
        if pos > 800 and not ping-sent:
          print "Send ping"
          web-socket.ping "hello"
          ping-sent = true
      writer.close

client-reading web-socket -> none:
  TEST-PACKETS.do: | packet |
    // Receive with a reader.
    2.repeat:
      reader := web-socket.start-receiving
      size := 0
      ba := #[]
      while ba.size < packet.size:
        ba += reader.read
      expect-equals null reader.read
      expect reader.is-text == (packet is string)
      if reader.is-text:
        expect-equals packet ba.to-string
      else:
        expect-equals ba packet
    // Receive with a single call to `receive`.
    2.repeat:
      round-trip-packet := web-socket.receive
      expect-equals packet round-trip-packet
  web-socket.close

start-server network -> int:
  server-socket := network.tcp-listen 0
  port := server-socket.local-address.port
  server := http.Server
  task --background::
    server.listen server-socket:: | request/http.RequestIncoming response-writer/http.ResponseWriter |
      if request.path == "/":
        web-socket := server.web-socket request response-writer
        // For this test, the server end of the web socket just echoes back
        // what it gets.
        while data := web-socket.receive:
          sent-but-not-reflected--
          web-socket.send data
        sleep --ms=10  // Give the client some time to count up before we check the result.
        expect-equals 0 sent-but-not-reflected
        web-socket.close
      else:
        response-writer.write-headers http.STATUS-NOT-FOUND --message="Not Found"
  return port

unmark-bytes-test -> none:
  mask := ByteArray 4: it * 17 + 2
  for offset := 0; offset < 4; offset++:
    for size := 98; size < 102; size++:
      data := ByteArray size: it
      FragmentReader_.unmask-bytes_ data mask offset
      data.size.repeat:
        expect-equals data[it] (it ^ mask[(it + offset) & 3])
