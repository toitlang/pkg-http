// Copyright (C) 2025 Toit contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import certificate-roots
import http
import net
import system
import tls
import .server-tls as server

main args:
  if args.size > 1:
    print "Usage: $system.program-name [port]"
    exit 1

  port := args.size == 1 ? int.parse args[0] : 8080
  root-cert := tls.RootCertificate server.SERVER-CERT-RAW
  root-cert.install

  network := net.open
  client := http.Client network
  response := client.get --uri="https://localhost:$port/json"
  while data := response.body.read:
    print data.to-string

  client.close
