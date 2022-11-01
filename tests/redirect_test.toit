// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import http
import net
import encoding.json
import certificate_roots

HOST ::= "httpbin.org"
PATH_GET ::= "/absolute-redirect/3"

PATH_POST     ::= "/redirect-to?url=http%3A%2F%2Fhttpbin.org%2F%2Fpost&status_code=302"
PATH_POST_TLS ::= "/redirect-to?url=https%3A%2F%2Fhttpbin.org%2F%2Fpost&status_code=302"
PATH_POST303  ::= "/redirect-to?url=http%3A%2F%2Fhttpbin.org%2F%2Fget&status_code=303"

drain response/http.Response:
  while response.body.read: null

check_get_response response/http.Response --scheme:
  data := #[]
  while chunk := response.body.read:
    data += chunk
  expect_equals 200 response.status_code
  decoded := json.decode data
  expect_equals "$scheme://httpbin.org/get" decoded["url"]

test_get network/net.Interface --do_drain/bool=false:
  print "Get$(do_drain ? " (manual drain)" : "")"
  client := http.Client network

  response := client.get HOST PATH_GET
  check_get_response response --scheme="http"

  response = client.get HOST PATH_GET --no-follow_redirects
  expect_equals 302 response.status_code
  if do_drain:
    drain response
  client.close

test_post network/net.Interface --do_drain/bool=false:
  print "Post$(do_drain ? " (manual drain)" : "")"
  client := http.Client network --root_certificates=[certificate_roots.STARFIELD_CLASS_2_CA]

  response := client.post --host=HOST --path=PATH_POST #['h', 'e', 'l', 'l', 'o']
  data := #[]
  while chunk := response.body.read:
    data += chunk
  expect_equals 200 response.status_code
  decoded := json.decode data
  expect_equals "hello" decoded["data"]

  // Test that we can redirect from an HTTP to an HTTPS location.
  response = client.post --host=HOST --path=PATH_POST_TLS #['h', 'e', 'l', 'l', 'o']
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect_equals 200 response.status_code
  decoded = json.decode data
  expect_equals "hello" decoded["data"]

  // Test that we see the redirect if we ask not to follow redirects.
  response = client.post --host=HOST --path=PATH_POST #['h', 'e', 'l', 'l', 'o'] --no-follow_redirects
  expect_equals 302 response.status_code
  if do_drain:
    drain response

  response = client.post_json --host=HOST --path=PATH_POST "hello"
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect_equals 200 response.status_code
  decoded = json.decode data
  expect_equals "hello" (json.decode decoded["data"].to_byte_array)

  response = client.post_json --host=HOST --path=PATH_POST "hello" --no-follow_redirects
  expect_equals 302 response.status_code
  if do_drain:
    drain response

  response = client.post_form --host=HOST --path=PATH_POST { "toit": "hello" }
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect_equals 200 response.status_code
  decoded = json.decode data
  expect_equals "hello" decoded["form"]["toit"]

  response = client.post_form --host=HOST --path=PATH_POST { "toit": "hello" } --no-follow_redirects
  expect_equals 302 response.status_code
  if do_drain:
    drain response

  // A post to a redirect 303 should become a GET.
  response = client.post --host=HOST --path=PATH_POST303 #['h', 'e', 'l', 'l', 'o']
  data = #[]
  while chunk := response.body.read:
    data += chunk
  expect_equals 200 response.status_code
  decoded = json.decode data
  expect decoded["args"].is_empty

  response = client.post --host=HOST --path=PATH_POST303 #['h', 'e', 'l', 'l', 'o'] --no-follow_redirects
  expect_equals 303 response.status_code
  if do_drain:
    drain response

  client.close

main:
  network := net.open

  test_get network
  test_get network --do_drain
  test_post network
  test_post network --do_drain

  print "Closing network"
  network.close
