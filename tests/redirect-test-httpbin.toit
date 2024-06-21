// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import net
import encoding.json
import encoding.url
import certificate-roots

// For testing the HOST url might be rewritten to a localhost.
HOST := "httpbin.org"
PORT/int? := null
HOST-PORT := PORT ? "$HOST:$PORT" : HOST
PATH-GET ::= "/absolute-redirect/3"

PATH-POST     ::= "/redirect-to?url=$(url.encode "http://$HOST-PORT/post")&status_code=302"
PATH-POST-TLS ::= "/redirect-to?url=$(url.encode "https://$HOST-PORT/post")&status_code=302"
PATH-POST303  ::= "/redirect-to?url=$(url.encode "http://$HOST-PORT/get")&status_code=303"

check-get-response response/http.Response --scheme:
  data := #[]
  while chunk := response.body.read:
    data += chunk
  expect-equals 200 response.status-code
  decoded := json.decode data
  host-port := HOST
  if PORT: host-port += ":$PORT"
  expect-equals "$scheme://$host-port/get" decoded["url"]

test-get network/net.Interface --do-drain/bool=false:
  print "Get$(do-drain ? " (manual drain)" : "")"
  client := http.Client network

  response := client.get HOST --port=PORT PATH-GET
  check-get-response response --scheme="http"

  response = client.get HOST --port=PORT PATH-GET --no-follow-redirects
  expect-equals 302 response.status-code
  if do-drain:
    response.drain
  client.close

test-post network/net.Interface --do-drain/bool=false:
  print "Post$(do-drain ? " (manual drain)" : "")"
  client := http.Client network --root-certificates=[certificate-roots.STARFIELD-CLASS-2-CA]

  response := client.post --host=HOST --port=PORT --path=PATH-POST #['h', 'e', 'l', 'l', 'o']
  data := #[]
  while chunk := response.body.read:
    data += chunk
  expect-equals 200 response.status-code
  decoded := json.decode data
  expect-equals "hello" decoded["data"]

  if HOST == "httpbin.org":
    // Test that we can redirect from an HTTP to an HTTPS location.
    response = client.post --host=HOST --port=PORT --path=PATH-POST-TLS #['h', 'e', 'l', 'l', 'o']
    data = #[]
    while chunk := response.body.read:
      data += chunk
    expect-equals 200 response.status-code
    decoded = json.decode data
    expect-equals "hello" decoded["data"]

  // Test that we see the redirect if we ask not to follow redirects.
  response = client.post --host=HOST --port=PORT --path=PATH-POST #['h', 'e', 'l', 'l', 'o'] --no-follow-redirects
  expect-equals 302 response.status-code
  if do-drain:
    response.drain

  response = client.post-json --host=HOST --port=PORT --path=PATH-POST "hello"
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect-equals 200 response.status-code
  decoded = json.decode data
  expect-equals "hello" (json.decode decoded["data"].to-byte-array)

  response = client.post-json --host=HOST --port=PORT --path=PATH-POST "hello" --no-follow-redirects
  expect-equals 302 response.status-code
  if do-drain:
    response.drain

  response = client.post-form --host=HOST --port=PORT --path=PATH-POST { "toit": "hello" }
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect-equals 200 response.status-code
  decoded = json.decode data
  expect-equals "hello" decoded["form"]["toit"]

  response = client.post-form --host=HOST --port=PORT --path=PATH-POST { "toit": "hello" } --no-follow-redirects
  expect-equals 302 response.status-code
  if do-drain:
    response.drain

  // A post to a redirect 303 should become a GET.
  response = client.post --host=HOST --port=PORT --path=PATH-POST303 #['h', 'e', 'l', 'l', 'o']
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect-equals 200 response.status-code
  decoded = json.decode data
  expect decoded["args"].is-empty

  response = client.post --host=HOST --port=PORT --path=PATH-POST303 #['h', 'e', 'l', 'l', 'o'] --no-follow-redirects
  expect-equals 303 response.status-code
  if do-drain:
    response.drain

  client.close

main args:
  if not args.is-empty:
    host-port/string := args[0]
    if host-port.contains ":":
      parts := host-port.split --at-first ":"
      HOST = parts[0]
      PORT = int.parse parts[1]
    else:
      HOST = host-port

  if HOST == "httpbin.org":
    print "May timeout if httpbin is overloaded."

  network := net.open

  test-get network
  test-get network --do-drain
  test-post network
  test-post network --do-drain

  print "Closing network"
  network.close
  print "done"
