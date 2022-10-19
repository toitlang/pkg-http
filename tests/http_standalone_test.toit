// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import encoding.json
import expect show *
import http
import net

// Sets up a web server that can switch to websocket mode on the "/" path.
// The server just sends back everything it gets.
// Sets up a client that sends files and expects to receive them back.

main:
  network := net.open
  port := start_server network
  run_client network port

run_client network port/int -> none:
  client := http.Client network

  3.repeat:

    response := client.get --host="localhost" --port=port --path="/"

    page := ""
    while data := response.body.read:
      page += data.to_string
    expect_equals INDEX_HTML.size page.size

    response = client.get --host="localhost" --port=port --path="/cat.png"
    expect_equals "image/png"
        response.headers.single "Content-Type"
    size := 0
    while data := response.body.read:
      size += data.size

    expect_equals CAT.size size

    response = client.get --host="localhost" --port=port --path="/unobtainium.jpeg"
    expect_equals 404 response.status_code

    response = client.get --host="localhost" --port=port --path="/foo.json"
    expect_equals "application/json"
        response.headers.single "Content-Type"

    while data := response.body.read:
      //

start_server network -> int:
  server_socket := network.tcp_listen 0
  port := server_socket.local_address.port
  server := http.Server
  task --background::
    server.listen server_socket:: | request/http.Request response_writer/http.ResponseWriter |
      if request.path == "/":
        response_writer.headers.set "Content-Type" "text/html"
        response_writer.write INDEX_HTML
      else if request.path == "/foo.json":
        response_writer.headers.set "Content-Type" "application/json"
        response_writer.write
          json.encode {"foo": 123, "bar": 1.0/3, "fizz": [1, 42, 103]}
      else if request.path == "/cat.png":
        response_writer.headers.set "Content-Type" "image/png"
        response_writer.write CAT
      else:
        response_writer.write_headers http.STATUS_NOT_FOUND --message="Not Found"
  print "\nListening on http://localhost:$port/\n"
  return port

INDEX_HTML ::= """
    <html>
      <head>
        <title>This is the title</title>
      </head>
      <body>
        <h1>My oh my</h1>
        <p>What a page this is!</p>
        <br>
        <img src="/cat.png">
      </body>
    </html>"""

CAT ::= #[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x01, 0x40, 0x00, 0x00, 0x00, 0xf0, 0x08, 0x02, 0x00, 0x00, 0x00, 0xfe, 0x4f, 0x2a,
    0x3c, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 0x00, 0x00, 0x2e, 0x23, 0x00, 0x00, 0x2e,
    0x23, 0x01, 0x78, 0xa5, 0x3f, 0x76, 0x00, 0x00, 0x0c, 0x2d, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda,
    0xed, 0x9d, 0xdb, 0xd1, 0xdb, 0x38, 0x12, 0x46, 0x49, 0x95, 0x92, 0x70, 0x04, 0xf3, 0xe2, 0x2a,
    0xc7, 0xe3, 0x0c, 0x1c, 0x92, 0x33, 0x70, 0x3c, 0xae, 0x9a, 0x17, 0x47, 0x30, 0x61, 0x68, 0x1e,
    0x34, 0xa3, 0x52, 0x89, 0x12, 0x09, 0x02, 0xdd, 0x8d, 0xbe, 0x9c, 0xef, 0x69, 0x6b, 0xd7, 0xfb,
    0x8b, 0x20, 0xfa, 0xe0, 0x6b, 0x34, 0x71, 0x59, 0x6f, 0xb7, 0xdb, 0x82, 0x10, 0x8a, 0xa9, 0x0b,
    0xaf, 0x00, 0x21, 0x00, 0x46, 0x08, 0x01, 0x30, 0x42, 0x08, 0x80, 0x11, 0x02, 0x60, 0x84, 0x10,
    0x00, 0x23, 0x84, 0x00, 0x18, 0x21, 0x04, 0xc0, 0x08, 0x01, 0x30, 0x42, 0x08, 0x80, 0x11, 0x42,
    0x00, 0x8c, 0x10, 0x00, 0x23, 0x84, 0x00, 0x18, 0x21, 0x04, 0xc0, 0x08, 0x21, 0x00, 0x46, 0x08,
    0x80, 0x11, 0x42, 0x00, 0x8c, 0x10, 0x02, 0x60, 0x84, 0x10, 0x00, 0x23, 0x04, 0xc0, 0x08, 0x21,
    0x00, 0x46, 0x08, 0x01, 0x30, 0x42, 0x00, 0x8c, 0x10, 0x02, 0x60, 0x84, 0x10, 0x00, 0x23, 0x84,
    0x00, 0x18, 0xa1, 0xb4, 0xba, 0xf2, 0x0a, 0x50, 0x2c, 0xad, 0xeb, 0x3a, 0xf1, 0xd7, 0xbd, 0x5d,
    0x45, 0xb4, 0x72, 0x37, 0x12, 0x82, 0xdb, 0xb8, 0x18, 0x93, 0x42, 0x23, 0xe8, 0x0d, 0xfc, 0x3c,
    0x38, 0x30, 0x02, 0xdd, 0xc0, 0x3e, 0x8c, 0x03, 0x23, 0xe8, 0x0d, 0xfc, 0x78, 0x00, 0x8c, 0xc0,
    0x23, 0xb0, 0xa8, 0x42, 0x23, 0xd0, 0x0d, 0x2c, 0x1c, 0x18, 0x41, 0x2f, 0x0e, 0xac, 0xd9, 0x8b,
    0x94, 0xd9, 0xa0, 0x17, 0x85, 0x01, 0x78, 0xdb, 0x85, 0xf7, 0xff, 0x06, 0x8c, 0x41, 0x17, 0x79,
    0x07, 0x78, 0xa7, 0x17, 0x1f, 0xff, 0x13, 0x24, 0x43, 0xef, 0x43, 0xdf, 0xbe, 0xff, 0x54, 0x7d,
    0xb0, 0xdf, 0xbf, 0x7e, 0x78, 0x7f, 0x75, 0xae, 0x78, 0x38, 0xd5, 0x91, 0x90, 0x5c, 0x96, 0x5e,
    0x6d, 0x6e, 0xdb, 0x19, 0x9e, 0x1e, 0x84, 0xd7, 0xb8, 0x1d, 0xc9, 0x3c, 0xb9, 0xa0, 0x2c, 0xd1,
    0x25, 0x85, 0x9e, 0x03, 0x3f, 0x30, 0x67, 0xb5, 0x5f, 0xe8, 0xdd, 0xea, 0x92, 0x32, 0x26, 0xa8,
    0x88, 0x40, 0x2f, 0x0e, 0x9c, 0x33, 0x38, 0xf0, 0x67, 0x32, 0x67, 0x00, 0xce, 0x03, 0x36, 0x3c,
    0x3b, 0xb7, 0x5f, 0xd0, 0x05, 0xe0, 0x73, 0x61, 0x04, 0xd2, 0x18, 0x2f, 0x73, 0xe0, 0x1e, 0x39,
    0x21, 0x67, 0xfd, 0x5f, 0x04, 0x87, 0x93, 0xd9, 0x2f, 0xc2, 0x81, 0x87, 0x82, 0x0c, 0x4f, 0x4e,
    0x93, 0x3c, 0xbf, 0x7c, 0xd4, 0x4d, 0xe0, 0xf0, 0x00, 0x0c, 0xc9, 0x25, 0x92, 0xe7, 0xb7, 0xeb,
    0x31, 0x7e, 0xff, 0xfa, 0x11, 0x9d, 0x61, 0x5f, 0x9f, 0x91, 0x9c, 0x13, 0x42, 0x76, 0x1d, 0x31,
    0x79, 0xfe, 0xfd, 0xeb, 0xc7, 0xce, 0x6a, 0x2a, 0xff, 0x8b, 0x25, 0x23, 0x01, 0xdc, 0x3e, 0x3c,
    0xcf, 0x1d, 0x38, 0xc1, 0x38, 0x8a, 0xfd, 0x0e, 0xf2, 0xe9, 0x1f, 0x6f, 0x77, 0x29, 0xf4, 0xed,
    0x76, 0xeb, 0x98, 0x23, 0x4d, 0x79, 0xd1, 0x6c, 0x93, 0xca, 0x4d, 0x2f, 0x0e, 0xac, 0x98, 0x14,
    0xbd, 0xf5, 0xe4, 0x29, 0xb6, 0x8c, 0x1b, 0x7b, 0xce, 0x9f, 0xd3, 0x2b, 0x5b, 0x11, 0xeb, 0x13,
    0xc3, 0xda, 0x83, 0x31, 0x6e, 0x8c, 0xfd, 0x02, 0xf0, 0xb9, 0xee, 0x39, 0xd5, 0xd9, 0x36, 0xf9,
    0x36, 0x18, 0x97, 0xb2, 0x5f, 0x0f, 0x1d, 0x7d, 0xf5, 0xf9, 0x5e, 0x54, 0x3b, 0x7b, 0x4b, 0xbe,
    0x2c, 0xd2, 0xeb, 0xca, 0x69, 0xdb, 0xd8, 0x2f, 0x0e, 0x2c, 0x6d, 0xc2, 0x96, 0xfe, 0x8c, 0x15,
    0x4f, 0xb4, 0xdf, 0x3a, 0xf4, 0xfa, 0x05, 0x58, 0xdb, 0x84, 0x5b, 0x60, 0x1e, 0x8f, 0x03, 0xac,
    0xd8, 0xde, 0x7e, 0x4b, 0xd1, 0xbb, 0x44, 0xdf, 0x0f, 0xac, 0xda, 0x5b, 0x13, 0x2b, 0xdb, 0xd8,
    0x2f, 0xf4, 0x96, 0x00, 0xd8, 0xcc, 0x1c, 0xba, 0x31, 0xe6, 0xc3, 0x09, 0x99, 0x73, 0xd1, 0x39,
    0xf0, 0xc4, 0x2c, 0x5a, 0x3b, 0xb5, 0x0e, 0x6a, 0x74, 0x7a, 0xd3, 0x81, 0xf1, 0x34, 0x47, 0xa3,
    0x53, 0x42, 0x8c, 0x08, 0xae, 0x8b, 0x58, 0x2d, 0x0c, 0xb7, 0x94, 0xb2, 0xde, 0xf6, 0x44, 0x77,
    0xd0, 0xdc, 0xff, 0x8f, 0xed, 0xbd, 0x2b, 0x38, 0x13, 0x9e, 0x3b, 0xa2, 0xf5, 0xed, 0x9d, 0x36,
    0x78, 0xe6, 0x9a, 0xde, 0x5b, 0x25, 0x85, 0xfe, 0xd4, 0xbb, 0xfb, 0x6b, 0xdc, 0x0d, 0x4c, 0xa3,
    0x91, 0x99, 0x67, 0x39, 0xf4, 0xfc, 0xf1, 0xa7, 0x1a, 0x79, 0x93, 0xed, 0x9d, 0x98, 0xb5, 0x96,
    0xe1, 0x1d, 0xe0, 0x96, 0x31, 0x7e, 0x64, 0xaf, 0xc9, 0x20, 0xc3, 0x8d, 0x61, 0xf1, 0x29, 0xca,
    0xd7, 0x23, 0x85, 0x88, 0xa1, 0x96, 0xe3, 0xf8, 0x35, 0xc6, 0xe5, 0xf6, 0xbe, 0x4b, 0x5c, 0x89,
    0xa4, 0x88, 0x35, 0x9a, 0x80, 0x9d, 0x0a, 0x8e, 0x88, 0x7c, 0x9a, 0x59, 0xb1, 0x06, 0xba, 0x4b,
    0xf6, 0x73, 0x79, 0x2e, 0x40, 0x68, 0xc3, 0x70, 0x85, 0x3d, 0x0f, 0x2f, 0x0d, 0x6c, 0x69, 0x6f,
    0x3b, 0x5d, 0x77, 0x6e, 0xcf, 0xf6, 0x94, 0x1e, 0xbd, 0x4e, 0xbe, 0xf0, 0x07, 0x58, 0x89, 0x65,
    0x53, 0x8e, 0x7e, 0x44, 0x46, 0x5f, 0x97, 0x7f, 0xfb, 0xfe, 0xb3, 0x72, 0x29, 0x45, 0x35, 0x79,
    0xee, 0x7b, 0xb1, 0x45, 0x3e, 0xe0, 0xe7, 0xd9, 0x8d, 0x24, 0xb5, 0xb2, 0xf2, 0x1e, 0x2e, 0xac,
    0xdf, 0xe8, 0xe6, 0xb6, 0xdd, 0x9a, 0xfa, 0x3e, 0x1f, 0x80, 0x6e, 0xbc, 0x14, 0xda, 0x3e, 0x5d,
    0x19, 0xac, 0x51, 0x17, 0x67, 0x58, 0xc4, 0x7e, 0x79, 0xff, 0x85, 0xe6, 0xc0, 0x1e, 0xa6, 0xd6,
    0x98, 0xf6, 0x74, 0x9f, 0x2c, 0xb8, 0xf4, 0x35, 0x4c, 0x0a, 0x2d, 0xb5, 0xa8, 0x63, 0x56, 0x66,
    0x1e, 0x14, 0x8f, 0x40, 0x36, 0x28, 0xdb, 0x4d, 0x51, 0x1a, 0xce, 0xb1, 0xb2, 0x92, 0x0c, 0x1b,
    0x97, 0xb2, 0x0c, 0x46, 0x16, 0xa5, 0xbd, 0xd3, 0xb2, 0x4f, 0x5e, 0x39, 0xf7, 0x89, 0x94, 0x42,
    0x77, 0x2c, 0xea, 0x48, 0x66, 0x44, 0xf7, 0xe6, 0xcc, 0xdd, 0x26, 0x35, 0xfe, 0xd3, 0x82, 0x4f,
    0xce, 0x76, 0x31, 0x1c, 0x58, 0x3e, 0xbe, 0x55, 0x6b, 0xa7, 0x4e, 0xe2, 0x55, 0xbb, 0x99, 0xfb,
    0x3f, 0xa1, 0xfd, 0x12, 0x02, 0x4d, 0x1c, 0x82, 0xed, 0x38, 0xef, 0xbb, 0x95, 0xc3, 0x3e, 0xeb,
    0x6b, 0xf9, 0xc5, 0x04, 0xd6, 0x61, 0xb0, 0xac, 0xe2, 0xf9, 0x27, 0x06, 0xdf, 0x58, 0xfb, 0x70,
    0x70, 0xd8, 0x2e, 0x3f, 0xd4, 0x04, 0x73, 0xe0, 0xbe, 0x45, 0x1d, 0xf6, 0xab, 0x2c, 0x26, 0xba,
    0x47, 0xbe, 0x8c, 0xc6, 0xf9, 0xa8, 0x04, 0xc0, 0xb1, 0x53, 0xdf, 0xc4, 0x06, 0x2b, 0xfb, 0xd2,
    0xd2, 0xbc, 0x10, 0x57, 0x49, 0xeb, 0xa5, 0xc8, 0xeb, 0x6b, 0x89, 0x9e, 0x47, 0x71, 0x68, 0xfb,
    0x8f, 0xb1, 0xcd, 0x1c, 0x53, 0xf7, 0x64, 0xf6, 0x9b, 0xd6, 0x81, 0xdf, 0x7e, 0xf8, 0xa9, 0x69,
    0x17, 0x66, 0x0c, 0xef, 0xbc, 0xdb, 0x4c, 0x2f, 0xd3, 0x5b, 0xcd, 0xe8, 0xc2, 0x4b, 0x0c, 0x3a,
    0xf4, 0x86, 0xb0, 0x62, 0x3e, 0xf3, 0xe0, 0xc0, 0x28, 0x5b, 0x3a, 0x8d, 0xaa, 0x3b, 0x30, 0x42,
    0x53, 0x26, 0xc0, 0x0e, 0xbf, 0xb9, 0x5e, 0x4a, 0x75, 0x06, 0x16, 0x81, 0x70, 0x60, 0x84, 0x10,
    0x00, 0x8f, 0x89, 0x2b, 0x4b, 0x90, 0xc8, 0x14, 0xbd, 0xfd, 0xb8, 0x6f, 0x9f, 0x21, 0x77, 0xa1,
    0x17, 0x1d, 0xce, 0xb5, 0x90, 0x4d, 0xef, 0x27, 0x98, 0x52, 0x65, 0xae, 0x42, 0x7b, 0xdb, 0xca,
    0xfb, 0xcc, 0xed, 0x96, 0x61, 0xe6, 0xe7, 0x75, 0x46, 0x70, 0x1c, 0xb8, 0x29, 0xa5, 0xf9, 0xd4,
    0x55, 0xfb, 0xa9, 0xd4, 0x2c, 0xd7, 0xe5, 0x10, 0x1f, 0xa6, 0x6c, 0x38, 0xf0, 0x89, 0x61, 0x58,
    0x70, 0x9b, 0x8b, 0x60, 0xce, 0x3c, 0x78, 0x38, 0x66, 0xa0, 0xe4, 0x88, 0x04, 0x44, 0x44, 0xb1,
    0x2f, 0xb0, 0xdd, 0xdf, 0x99, 0xa4, 0x1a, 0x13, 0x36, 0x6e, 0x99, 0x26, 0xac, 0xfd, 0xef, 0xaf,
    0xdc, 0x7f, 0x42, 0x1c, 0x38, 0xb9, 0x81, 0xa8, 0xfe, 0x50, 0x5c, 0x8c, 0x4f, 0xbd, 0x28, 0xcf,
    0xc7, 0x8f, 0xb9, 0xbd, 0xab, 0x9d, 0xef, 0xc0, 0x7e, 0xe9, 0x9d, 0xf8, 0x8b, 0x22, 0xcf, 0xdc,
    0xf1, 0xd8, 0x14, 0x02, 0x70, 0xe0, 0x9c, 0x2c, 0x45, 0xb1, 0x62, 0x91, 0xf7, 0x63, 0x59, 0x9e,
    0x00, 0x60, 0xe8, 0x05, 0x63, 0xc5, 0x97, 0x53, 0xa4, 0xaa, 0x47, 0x0a, 0xcd, 0x38, 0x92, 0xfc,
    0x91, 0x54, 0xb3, 0xeb, 0xb8, 0x79, 0x3b, 0x00, 0x87, 0xec, 0xe3, 0xb2, 0x0f, 0xc3, 0x0c, 0x19,
    0x80, 0xf3, 0x0c, 0x28, 0x1e, 0xa2, 0xb9, 0x48, 0x49, 0xcf, 0xed, 0x67, 0xa4, 0x4b, 0xee, 0x10,
    0x87, 0xf3, 0x94, 0x6f, 0x58, 0xf6, 0x77, 0x43, 0xc7, 0x09, 0x0e, 0xec, 0x48, 0xff, 0xfc, 0xfd,
    0x17, 0x83, 0x94, 0xc3, 0x86, 0x7b, 0x5e, 0xec, 0x44, 0x15, 0xda, 0x14, 0xbf, 0x2f, 0x5f, 0xff,
    0xb4, 0xfc, 0x91, 0xc3, 0x7f, 0xf6, 0x12, 0xca, 0x53, 0x2a, 0xb4, 0x24, 0x38, 0x38, 0x70, 0x69,
    0xf3, 0x14, 0xfc, 0x6b, 0xac, 0x2d, 0xd1, 0x6b, 0x88, 0xf3, 0xb5, 0xc6, 0xc9, 0x01, 0x8e, 0x15,
    0x67, 0xcf, 0xc6, 0xeb, 0x9f, 0x61, 0xd9, 0x01, 0x4b, 0x76, 0x04, 0xc4, 0x81, 0x63, 0xa8, 0x7b,
    0x47, 0x61, 0xca, 0xb0, 0x36, 0x5e, 0xa1, 0x2d, 0xfe, 0xfc, 0xf7, 0x7f, 0x0f, 0xc9, 0x38, 0x70,
    0xb6, 0xe4, 0xbc, 0x3d, 0xa6, 0x6d, 0x16, 0x54, 0x68, 0xcf, 0x29, 0xcc, 0x30, 0x4e, 0x30, 0x11,
    0x00, 0xe0, 0x8a, 0x73, 0xec, 0x10, 0x4f, 0xee, 0xa1, 0xc9, 0xfe, 0x37, 0xdb, 0x02, 0xb0, 0xfc,
    0xf4, 0x55, 0xe9, 0xef, 0x78, 0x08, 0x68, 0x03, 0xfb, 0xf5, 0xd6, 0x16, 0x00, 0x46, 0x27, 0x22,
    0x7b, 0xff, 0x1f, 0xcc, 0x05, 0xa3, 0x9b, 0xde, 0xa0, 0xe9, 0x43, 0x88, 0xb3, 0x2e, 0xa8, 0x42,
    0x23, 0xa7, 0xde, 0x2b, 0x95, 0xd4, 0xe4, 0x16, 0x0e, 0xbc, 0xc4, 0x0a, 0xb8, 0x94, 0x45, 0x5a,
    0x58, 0x05, 0x60, 0x02, 0x11, 0xfb, 0xad, 0x28, 0x96, 0x52, 0xaa, 0x30, 0x5c, 0xf0, 0x63, 0xa6,
    0x54, 0x93, 0x6d, 0xd0, 0x8d, 0xbe, 0x00, 0xab, 0x90, 0x03, 0x4b, 0x4d, 0x83, 0x4f, 0xad, 0x09,
    0xf9, 0xf2, 0xf5, 0x8f, 0x52, 0x20, 0xe6, 0xb6, 0xa6, 0xf6, 0xd6, 0x71, 0x40, 0x47, 0x12, 0x07,
    0xbe, 0xdd, 0x6e, 0x13, 0x0f, 0x97, 0x35, 0x76, 0x63, 0xb7, 0xf4, 0x8e, 0xb7, 0x91, 0x9c, 0x19,
    0x07, 0xf6, 0xeb, 0x2a, 0x22, 0x86, 0xdc, 0xf8, 0x17, 0x7c, 0x16, 0xde, 0x65, 0xe7, 0x14, 0x83,
    0x83, 0x72, 0xa6, 0x6f, 0x13, 0x00, 0x6c, 0x17, 0x37, 0x87, 0x18, 0x7f, 0x8a, 0xf2, 0x53, 0xfc,
    0xa7, 0xcf, 0x2d, 0x0d, 0x1a, 0x18, 0xe8, 0xb6, 0x03, 0x8a, 0x58, 0xa7, 0xa3, 0xc7, 0x72, 0xfc,
    0x8e, 0x92, 0x58, 0x1e, 0xee, 0xa3, 0xf2, 0xd3, 0x90, 0x64, 0x4b, 0x03, 0x00, 0xd8, 0x11, 0xc3,
    0x39, 0xe6, 0x81, 0xaa, 0xad, 0xc0, 0x7e, 0x49, 0xa1, 0x63, 0x84, 0x51, 0xb2, 0x07, 0x73, 0xd2,
    0xba, 0x7c, 0x2b, 0xf3, 0x00, 0xb8, 0x3f, 0x98, 0xbc, 0xd1, 0x02, 0xbd, 0xd5, 0xec, 0x77, 0xe1,
    0x3b, 0x70, 0x1a, 0x66, 0x12, 0xd3, 0xeb, 0x70, 0xac, 0x04, 0x60, 0x9c, 0x61, 0xda, 0x33, 0xdc,
    0x0f, 0x94, 0x3e, 0x35, 0xae, 0x4d, 0x6c, 0xa3, 0xe0, 0x4f, 0xa7, 0xdc, 0xd9, 0x12, 0xfb, 0x7e,
    0xe0, 0xff, 0xda, 0xb0, 0xbb, 0x90, 0xc3, 0x2c, 0xfe, 0xa6, 0xc4, 0xc7, 0xd9, 0xa6, 0x8d, 0xdc,
    0xac, 0x6d, 0xdf, 0x40, 0xd9, 0x8e, 0x4b, 0xb3, 0x7c, 0x12, 0x80, 0x93, 0x90, 0x3c, 0x4e, 0xaf,
    0x5b, 0x86, 0xc5, 0xbb, 0xac, 0xe5, 0xc9, 0x01, 0x18, 0x86, 0x8d, 0xc2, 0xbd, 0xa3, 0x39, 0xfb,
    0x0f, 0xe3, 0x87, 0x61, 0xa5, 0x9e, 0xca, 0x0a, 0x30, 0xdf, 0x81, 0x2d, 0x62, 0x51, 0x30, 0xe8,
    0xa7, 0x4f, 0xb9, 0xef, 0x0f, 0x20, 0x8e, 0xb1, 0x6a, 0xbb, 0xb2, 0xd2, 0x8b, 0x03, 0x4f, 0xd0,
    0x48, 0xe8, 0x77, 0xb7, 0xa2, 0xe5, 0x47, 0x55, 0xff, 0xb8, 0xff, 0xda, 0x04, 0x00, 0xbb, 0x06,
    0x78, 0x71, 0xf9, 0xa1, 0xc5, 0xe6, 0x56, 0x94, 0xc6, 0x08, 0x16, 0x79, 0x92, 0x59, 0xf7, 0xbc,
    0xd4, 0xa4, 0x37, 0x4f, 0x0a, 0x7d, 0xb8, 0xa9, 0xd0, 0x79, 0x8e, 0x1d, 0x71, 0x1e, 0x1e, 0x65,
    0x94, 0x94, 0x32, 0x00, 0x9f, 0x90, 0xf3, 0x1d, 0x38, 0xb3, 0x4e, 0xd1, 0xcb, 0x01, 0x80, 0x87,
    0x90, 0x8b, 0x08, 0x80, 0x63, 0x78, 0x11, 0x0a, 0xd1, 0xe3, 0xb7, 0x36, 0x91, 0x42, 0x93, 0x45,
    0x7b, 0x1f, 0xb0, 0x92, 0x2d, 0x57, 0x94, 0x1d, 0xaf, 0xdd, 0x32, 0x4c, 0x0a, 0x0d, 0xbd, 0x28,
    0xb0, 0x00, 0x18, 0xd5, 0x1d, 0xbf, 0x12, 0x7c, 0x82, 0xb9, 0xd0, 0xaf, 0x34, 0x33, 0x59, 0xfe,
    0x5c, 0x2a, 0xfb, 0x48, 0x05, 0x70, 0xee, 0xeb, 0x82, 0x09, 0x5f, 0xd9, 0xe6, 0xe7, 0x58, 0x01,
    0x81, 0x03, 0xa3, 0x8a, 0xca, 0x41, 0xef, 0xc2, 0x5a, 0x68, 0x14, 0x2e, 0x31, 0x79, 0x8c, 0xc2,
    0xdb, 0xc7, 0xae, 0x33, 0xf5, 0x95, 0x01, 0x58, 0xe9, 0xb3, 0x4d, 0xa6, 0xf7, 0x8b, 0x6c, 0xf2,
    0xa9, 0xf6, 0x93, 0x06, 0x93, 0x45, 0xd7, 0xd0, 0x5a, 0xe8, 0xdc, 0xdf, 0x5d, 0x83, 0x4e, 0x98,
    0xeb, 0x54, 0xb0, 0x3a, 0x5a, 0x9a, 0xcf, 0x1b, 0x86, 0x1c, 0x58, 0xe9, 0x75, 0xb0, 0x1e, 0x83,
    0x71, 0xea, 0xd4, 0x93, 0xd7, 0xf4, 0x5e, 0xbf, 0x73, 0x60, 0xed, 0xa4, 0x20, 0xfd, 0xe9, 0x8d,
    0xd4, 0xea, 0xea, 0x28, 0x5b, 0x15, 0x9a, 0xf9, 0xf3, 0x52, 0xec, 0xe6, 0xbe, 0xca, 0xf6, 0xbb,
    0xd4, 0x5c, 0x89, 0x55, 0xc1, 0xa0, 0x1a, 0x19, 0x8e, 0x8e, 0x7a, 0x71, 0x7a, 0x17, 0x96, 0x52,
    0x16, 0x1f, 0xa4, 0xce, 0x9e, 0x2f, 0x1b, 0x74, 0x20, 0x4e, 0x5c, 0x55, 0x59, 0xf3, 0x0d, 0x4e,
    0x8d, 0xbd, 0x95, 0x3b, 0xcf, 0xec, 0xc3, 0x32, 0xd0, 0x3b, 0x39, 0xb5, 0xe2, 0xea, 0x39, 0x24,
    0xf8, 0x8c, 0x94, 0x84, 0xe1, 0xc4, 0x00, 0xc7, 0x3a, 0x71, 0x4e, 0x9b, 0xde, 0x4f, 0x51, 0x91,
    0xe4, 0x30, 0x29, 0x00, 0xf6, 0x10, 0x7c, 0xb9, 0xef, 0x1f, 0x30, 0x3e, 0x9f, 0x7d, 0x1f, 0xd1,
    0x6d, 0x6c, 0x84, 0x46, 0x60, 0xcd, 0x3a, 0xbf, 0xf7, 0xc9, 0xb0, 0xd4, 0xe1, 0xcc, 0x81, 0xe8,
    0x15, 0x7f, 0xdb, 0x52, 0x85, 0xab, 0x1c, 0x24, 0x03, 0xb0, 0xbb, 0xc4, 0xaf, 0xef, 0xa9, 0x42,
    0xd4, 0xa2, 0xcc, 0x46, 0xa8, 0x53, 0x51, 0x1d, 0x9a, 0xe4, 0xb4, 0x55, 0xe8, 0x96, 0x3e, 0xf0,
    0x19, 0xf4, 0x1d, 0x95, 0x61, 0xf6, 0x39, 0x8f, 0xe0, 0xb7, 0x3d, 0xf8, 0x4a, 0xe3, 0xf4, 0x39,
    0x1c, 0x58, 0xc5, 0x84, 0x17, 0xf7, 0x57, 0x9f, 0x1d, 0x3e, 0x5e, 0x20, 0x7a, 0x0d, 0xce, 0x8e,
    0x1f, 0x8f, 0xe7, 0x58, 0x86, 0x9c, 0x79, 0x3b, 0x61, 0xe3, 0x31, 0x77, 0x2f, 0xc1, 0xe1, 0xb3,
    0xe2, 0xfa, 0xf6, 0xa9, 0x58, 0x32, 0xa9, 0x9a, 0xbb, 0x3d, 0x82, 0xe7, 0xfe, 0x1f, 0x7c, 0x62,
    0xbc, 0xe6, 0x5e, 0x7b, 0x78, 0x36, 0x11, 0x9a, 0x7e, 0x43, 0x4f, 0x6e, 0x69, 0x3b, 0xb0, 0x46,
    0x30, 0x3b, 0xff, 0xf8, 0x74, 0x05, 0x5d, 0x9f, 0xc6, 0xab, 0x07, 0x4f, 0xb8, 0x71, 0xa4, 0x63,
    0xc5, 0x95, 0x20, 0x66, 0x2f, 0x86, 0xec, 0x6d, 0x4d, 0x48, 0x6c, 0x07, 0x6e, 0xbc, 0x11, 0xc3,
    0xcf, 0x64, 0x78, 0x16, 0x3c, 0x1e, 0x32, 0x70, 0x1b, 0xfb, 0xd5, 0x9e, 0xc1, 0x7a, 0x9b, 0x21,
    0x07, 0x03, 0xb8, 0x11, 0xc5, 0x6d, 0xa3, 0x2a, 0x33, 0x2c, 0x75, 0x0f, 0xf8, 0x14, 0x80, 0xbb,
    0x93, 0xe7, 0xb7, 0x3d, 0x2e, 0x18, 0xed, 0x4e, 0x48, 0x0e, 0x00, 0xf0, 0x27, 0xf6, 0x06, 0xbf,
    0xf5, 0x15, 0x61, 0xd8, 0xc9, 0xcd, 0xe6, 0xda, 0x1f, 0xb7, 0xf7, 0x83, 0x61, 0xa7, 0xf7, 0xc5,
    0xab, 0xd6, 0xc6, 0x40, 0xcd, 0x07, 0xf8, 0xd4, 0x64, 0xd5, 0xe6, 0x00, 0x20, 0xe7, 0x1f, 0x96,
    0x8a, 0x4c, 0xec, 0x4f, 0xbd, 0x9f, 0xf6, 0xc0, 0x38, 0x0c, 0x83, 0xbe, 0x18, 0x9b, 0x65, 0xc8,
    0xd6, 0x00, 0x9b, 0xe1, 0x3a, 0xfe, 0xeb, 0xa1, 0x31, 0x2e, 0xb2, 0xd1, 0x57, 0x2a, 0x54, 0x04,
    0x2d, 0x5a, 0x24, 0x61, 0xf4, 0x05, 0xb0, 0xd2, 0x98, 0xa7, 0x0d, 0xb0, 0x25, 0x06, 0xb2, 0x18,
    0x57, 0xa3, 0x77, 0xd1, 0xaf, 0x54, 0xb9, 0x75, 0x66, 0x45, 0x80, 0x8d, 0x87, 0xa2, 0xe8, 0x0c,
    0x4b, 0x91, 0x5c, 0x90, 0xde, 0xc5, 0xf6, 0x7c, 0x45, 0x11, 0x92, 0xa5, 0x1e, 0xd8, 0x02, 0x60,
    0x6f, 0x75, 0xb2, 0x8e, 0x65, 0xae, 0xdb, 0x8f, 0xa8, 0xda, 0x9c, 0xa4, 0xdf, 0x91, 0x2f, 0x3b,
    0x7e, 0x69, 0xc7, 0x98, 0x94, 0x91, 0x8a, 0x1b, 0xf2, 0x5a, 0xf3, 0x14, 0xb8, 0xc1, 0xa5, 0xea,
    0xf6, 0xb6, 0xcc, 0xad, 0x4e, 0x3e, 0x67, 0x61, 0xdd, 0xbf, 0x2b, 0xf6, 0x77, 0xca, 0x1e, 0xe3,
    0xd8, 0xc7, 0x70, 0xa9, 0x03, 0x1f, 0x03, 0xcd, 0x1d, 0xec, 0xc3, 0x58, 0xc3, 0x93, 0x3b, 0xfe,
    0xc2, 0x5a, 0xf9, 0x1c, 0x56, 0x18, 0x4e, 0x80, 0xee, 0xdc, 0x69, 0x9a, 0x38, 0xc6, 0xa7, 0x8b,
    0xde, 0x1c, 0xa4, 0x3c, 0x32, 0x25, 0x46, 0x1e, 0xe8, 0x5d, 0x1c, 0xd4, 0x59, 0xc6, 0x53, 0xe2,
    0xbe, 0x82, 0x19, 0x00, 0xc3, 0x70, 0x6c, 0x74, 0x9d, 0x00, 0x2c, 0xe5, 0xc9, 0x67, 0x31, 0x26,
    0x85, 0x1e, 0x12, 0x18, 0x7b, 0xa0, 0xd7, 0x1b, 0xc3, 0x8b, 0x61, 0xd5, 0xba, 0x22, 0xc0, 0x9f,
    0xb2, 0x1d, 0xa6, 0xc4, 0x3e, 0xd1, 0xbd, 0xbf, 0xe1, 0xa0, 0x97, 0x30, 0x88, 0x54, 0x9b, 0x77,
    0x22, 0xb3, 0x16, 0xc0, 0x2d, 0x15, 0x3f, 0x30, 0x8e, 0x4b, 0xaf, 0x4f, 0x86, 0x17, 0xb9, 0x5d,
    0xc4, 0xdb, 0xe0, 0xbc, 0x14, 0xe1, 0xf6, 0xf9, 0x98, 0xb2, 0x97, 0x13, 0xcc, 0x44, 0xba, 0x9f,
    0xd3, 0x36, 0xf4, 0xe8, 0x6d, 0x84, 0x76, 0x30, 0x93, 0x52, 0xd5, 0xcb, 0xe3, 0x75, 0x3f, 0xe1,
    0x6d, 0xa3, 0x5a, 0x87, 0xda, 0x29, 0xed, 0x40, 0xc4, 0x8d, 0xb5, 0xe9, 0x3d, 0xfc, 0xbf, 0xbf,
    0xa5, 0x37, 0xb1, 0x15, 0x27, 0x77, 0xe0, 0xed, 0x20, 0xb7, 0xef, 0xba, 0xb2, 0x99, 0x18, 0x6e,
    0x6c, 0xe9, 0xbd, 0x71, 0xad, 0x58, 0x26, 0xd4, 0xb3, 0xdd, 0xf5, 0x24, 0xbd, 0x64, 0x7c, 0x24,
    0x08, 0xb0, 0xe2, 0x0e, 0x7a, 0x3b, 0x4e, 0xff, 0x39, 0xbc, 0x42, 0x25, 0x73, 0x9a, 0x99, 0xa6,
    0x6d, 0x7a, 0x1d, 0xc6, 0xd7, 0xa6, 0xe9, 0xc6, 0xdb, 0x01, 0x70, 0x11, 0x8c, 0xc3, 0x03, 0x6c,
    0x73, 0xa0, 0x89, 0x48, 0x32, 0x56, 0x0a, 0x63, 0x11, 0xe3, 0x1d, 0x07, 0x38, 0x3d, 0xc6, 0xd7,
    0x04, 0xd0, 0x46, 0xe9, 0x18, 0xb3, 0xad, 0x88, 0x75, 0x66, 0xbc, 0xa7, 0xca, 0x19, 0x8f, 0x73,
    0x61, 0x33, 0x31, 0x7c, 0x0d, 0x8d, 0x6e, 0xd0, 0x9e, 0xd8, 0xb9, 0x6c, 0x01, 0x7a, 0x55, 0x31,
    0xce, 0xc7, 0xf0, 0x25, 0x22, 0xbd, 0xdb, 0xdb, 0xa8, 0x0c, 0xfa, 0xde, 0x43, 0xac, 0x43, 0xaf,
    0x54, 0x3f, 0x06, 0xba, 0xbe, 0x2c, 0xbc, 0x03, 0xa7, 0xbc, 0x58, 0x3d, 0x93, 0x15, 0xeb, 0xdd,
    0xdb, 0x46, 0x3a, 0x7d, 0x4c, 0x87, 0xdb, 0x06, 0x38, 0xbc, 0x24, 0xce, 0x60, 0xcc, 0x8e, 0x05,
    0xf3, 0x48, 0x12, 0x71, 0xaa, 0xa5, 0x83, 0x45, 0xac, 0xc3, 0x84, 0x0e, 0x07, 0x56, 0x44, 0xa5,
    0xd4, 0x6a, 0xed, 0x28, 0x85, 0xae, 0xc1, 0xfc, 0xdf, 0x43, 0xeb, 0x9e, 0xa7, 0xc4, 0x71, 0x23,
    0x6d, 0x75, 0xbb, 0x09, 0xcb, 0xf9, 0x3a, 0x38, 0x1b, 0x39, 0xc4, 0xd8, 0x1e, 0xdd, 0xf6, 0x75,
    0x94, 0x05, 0xe7, 0x68, 0x2e, 0x00, 0x0e, 0x74, 0xa5, 0xf2, 0x3e, 0xc3, 0x1d, 0x5b, 0x67, 0x02,
    0x91, 0x3c, 0xcb, 0x75, 0xb5, 0x01, 0xde, 0xef, 0x5c, 0xe7, 0x3c, 0x5f, 0x5d, 0xf1, 0x90, 0x23,
    0x5b, 0xd6, 0xc0, 0x78, 0x6e, 0xb9, 0xab, 0xc8, 0x69, 0xd5, 0x9f, 0xee, 0x37, 0x04, 0xe0, 0xcc,
    0x55, 0x84, 0xac, 0x18, 0x0b, 0x3e, 0x79, 0xac, 0xca, 0x5c, 0xac, 0x68, 0xbc, 0xce, 0x45, 0x77,
    0xc9, 0x5e, 0xa3, 0xd2, 0xb8, 0x56, 0x5b, 0x1b, 0x63, 0xee, 0x79, 0x01, 0x60, 0xe8, 0x55, 0x37,
    0x64, 0xf1, 0xd3, 0xde, 0xc5, 0xa7, 0xee, 0x36, 0xe8, 0x16, 0x3f, 0x95, 0xf1, 0x3a, 0x8b, 0xde,
    0x9a, 0xef, 0x5d, 0x16, 0x63, 0x11, 0x2b, 0xce, 0x5a, 0x72, 0x03, 0x60, 0xe8, 0x55, 0xc4, 0xd8,
    0x43, 0x46, 0x0d, 0xba, 0x09, 0xb4, 0xda, 0x5f, 0x2a, 0x13, 0x9a, 0xde, 0x96, 0xcf, 0x48, 0xfe,
    0x27, 0x9c, 0x81, 0xd0, 0x35, 0xfb, 0x86, 0x84, 0x03, 0x33, 0x63, 0x19, 0x8a, 0x7b, 0x11, 0xa8,
    0x5e, 0xfe, 0xc8, 0x16, 0x2a, 0x5c, 0x17, 0x80, 0x41, 0x37, 0x40, 0x5e, 0xfd, 0x92, 0x5d, 0x2b,
    0xed, 0x7c, 0x02, 0xdd, 0x72, 0x0e, 0x8c, 0xcc, 0xdc, 0x18, 0xd7, 0x05, 0x60, 0x34, 0x93, 0x64,
    0x9f, 0x1b, 0x86, 0x2d, 0xd1, 0xe5, 0x7c, 0x4f, 0x00, 0x06, 0xe3, 0xcc, 0x96, 0xcb, 0xbc, 0x0c,
    0x80, 0x8b, 0xe6, 0xd5, 0xe4, 0xc9, 0x00, 0x8c, 0xd2, 0x1a, 0x32, 0xe8, 0x02, 0x30, 0xd2, 0x42,
    0x4b, 0x8f, 0x61, 0x57, 0xdc, 0xf2, 0x05, 0xb8, 0x45, 0x5c, 0xf0, 0x7d, 0xf2, 0x7d, 0x1d, 0xed,
    0x35, 0x0b, 0x5a, 0xe3, 0x89, 0x78, 0x72, 0x00, 0xa1, 0xbb, 0x14, 0xb9, 0x9d, 0x30, 0xb1, 0x1b,
    0x8b, 0x80, 0x47, 0xc2, 0x4c, 0x0a, 0x8d, 0x26, 0xcf, 0x8d, 0x97, 0x62, 0x1f, 0x5d, 0xb0, 0x5f,
    0x1c, 0x38, 0x2d, 0xc9, 0xd8, 0x2f, 0x00, 0xa3, 0xf9, 0xf3, 0x52, 0x6d, 0x1a, 0xa5, 0x32, 0x70,
    0x34, 0x51, 0x14, 0xb1, 0xce, 0xbf, 0x32, 0xe9, 0x0d, 0x49, 0x66, 0x83, 0x48, 0x20, 0x5c, 0xa9,
    0x60, 0x31, 0x07, 0x2e, 0x9d, 0x4b, 0x3f, 0x03, 0x80, 0xcd, 0x02, 0x30, 0x2a, 0x31, 0x1f, 0x46,
    0xcc, 0x81, 0x11, 0x42, 0x00, 0x8c, 0x10, 0x02, 0x60, 0x94, 0x52, 0x54, 0xb0, 0x00, 0x18, 0xf9,
    0x15, 0xdb, 0x80, 0x01, 0x18, 0x21, 0x00, 0x46, 0x08, 0x01, 0x30, 0x42, 0xe4, 0xcf, 0x00, 0x8c,
    0xd0, 0xb2, 0x50, 0xc1, 0x02, 0x60, 0x84, 0x00, 0x18, 0x21, 0xec, 0x17, 0x80, 0x11, 0x62, 0x02,
    0x0c, 0xc0, 0x08, 0x01, 0x30, 0x42, 0x08, 0x80, 0x11, 0x22, 0x7f, 0x06, 0x60, 0x84, 0x5e, 0x44,
    0x05, 0x0b, 0x80, 0x11, 0x02, 0x60, 0x84, 0xb0, 0x5f, 0x00, 0x46, 0x88, 0x09, 0x30, 0x00, 0x23,
    0x04, 0xc0, 0x08, 0x21, 0x00, 0x46, 0x08, 0x01, 0x30, 0x42, 0x08, 0x80, 0x51, 0x10, 0x71, 0x8c,
    0x3b, 0x00, 0x23, 0x04, 0xc0, 0x08, 0x21, 0x00, 0x46, 0x08, 0x01, 0x30, 0x42, 0x08, 0x80, 0x91,
    0x6f, 0x51, 0xc1, 0x02, 0x60, 0x84, 0x00, 0x18, 0x21, 0x04, 0xc0, 0x08, 0x09, 0xe6, 0xcf, 0x08,
    0x80, 0x51, 0x60, 0x31, 0x01, 0x06, 0x60, 0x84, 0xfd, 0x02, 0x30, 0x5a, 0x96, 0x65, 0x59, 0xd6,
    0x75, 0xe5, 0x25, 0x20, 0x3f, 0xfa, 0x17, 0x0a, 0xdf, 0x50, 0xbb, 0xae, 0x88, 0xa8, 0xb8, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]
