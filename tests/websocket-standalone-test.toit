// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import net
import http.web_socket show FragmentReader_

// Sets up a web server that can switch to websocket mode on the "/" path.
// The server just sends back everything it gets.
// Sets up a client that sends files and expects to receive them back.

main:
  unmark_bytes_test
  client_server_test

client_server_test:
  network := net.open
  port := start_server network
  run_client network port

run_client network port/int -> none:
  client := http.Client network

  web_socket := client.web_socket --host="localhost" --port=port --path="/"

  task:: client_reading web_socket

  client_sending web_socket

  web_socket.close_write

TEST_PACKETS := [
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

sent_but_not_reflected := 0

client_sending web_socket -> none:
  TEST_PACKETS.do: | packet |
    2.repeat:
      // Send with a single call to `send`.
      sent_but_not_reflected++
      web_socket.send packet
      // Send with a writer.
      sent_but_not_reflected++
      writer := web_socket.start_sending
      pos := 0
      ping_sent := false
      print packet.size
      while pos < packet.size:
        pos += writer.write packet pos
        if pos > 800 and not ping_sent:
          print "Send ping"
          web_socket.ping "hello"
          ping_sent = true
      writer.close

client_reading web_socket -> none:
  TEST_PACKETS.do: | packet |
    // Receive with a reader.
    2.repeat:
      reader := web_socket.start_receiving
      size := 0
      ba := #[]
      while ba.size < packet.size:
        ba += reader.read
      expect_equals null reader.read
      expect reader.is_text == (packet is string)
      if reader.is_text:
        expect_equals packet ba.to_string
      else:
        expect_equals ba packet
    // Receive with a single call to `receive`.
    2.repeat:
      round_trip_packet := web_socket.receive
      expect_equals packet round_trip_packet
  web_socket.close

start_server network -> int:
  server_socket := network.tcp_listen 0
  port := server_socket.local_address.port
  server := http.Server
  task --background::
    server.listen server_socket:: | request/http.RequestIncoming response_writer/http.ResponseWriter |
      if request.path == "/":
        web_socket := server.web_socket request response_writer
        // For this test, the server end of the web socket just echoes back
        // what it gets.
        while data := web_socket.receive:
          sent_but_not_reflected--
          web_socket.send data
        sleep --ms=10  // Give the client some time to count up before we check the result.
        expect_equals 0 sent_but_not_reflected
        web_socket.close
      else:
        response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
  return port

unmark_bytes_test -> none:
  mask := ByteArray 4: it * 17 + 2
  for offset := 0; offset < 4; offset++:
    for size := 98; size < 102; size++:
      data := ByteArray size: it
      FragmentReader_.unmask_bytes_ data mask offset
      data.size.repeat:
        expect_equals data[it] (it ^ mask[(it + offset) & 3])
