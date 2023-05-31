// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import net
import net.x509
import certificate_roots

main:
  network := net.open
  client := http.Client.tls network
    --root_certificates=[certificate_roots.GLOBALSIGN_ROOT_CA,
                         certificate_roots.GTS_ROOT_R1]
  response := client.get "script.google.com" "/"
  while data := response.body.read:
  response = client.get "www.google.com" "/"
  while data := response.body.read:
  response = client.get "script.google.com" "/"
  while data := response.body.read:
