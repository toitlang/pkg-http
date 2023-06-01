// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import http
import net
import net.x509
import certificate_roots

main:
  network := net.open
  security_store := http.SecurityStoreInMemory
  client := http.Client.tls network
    --security_store=security_store
    --root_certificates=[certificate_roots.GLOBALSIGN_ROOT_CA,
                         certificate_roots.GTS_ROOT_R1]
  response := client.get "script.google.com" "/"
  while data := response.body.read:
  response = client.get "www.google.com" "/"
  while data := response.body.read:
  response = client.get "script.google.com" "/"
  while data := response.body.read:
  // Deliberately break the session state so that the server rejects our
  // attempt to use an abbreviated handshake.  We harmlessly retry without the
  // session data.
  security_store.session_data_["www.google.com:443"][15] ^= 42
  response = client.get "www.google.com" "/"
  while data := response.body.read:
