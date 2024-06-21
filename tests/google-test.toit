// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import http
import net
import certificate-roots

main:
  network := net.open
  security-store := http.SecurityStoreInMemory
  certificate-roots.install-common-trusted-roots
  client := http.Client.tls network
    --security-store=security-store
  response := client.get "script.google.com" "/"
  while data := response.body.read:
  response = client.get "www.google.com" "/"
  while data := response.body.read:
  response = client.get "script.google.com" "/"
  while data := response.body.read:
  // Deliberately break the session state so that the server rejects our
  // attempt to use an abbreviated handshake.  We harmlessly retry without the
  // session data.
  security-store.session-data_["www.google.com:443"][15] ^= 42
  response = client.get "www.google.com" "/"
  while data := response.body.read:
