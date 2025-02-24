// Copyright (C) 2025 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import certificate-roots
import http
import net
import system
import system.storage

/**
An example demonstrating the use of the SecurityStore to cache TLS
  session state data in RTC memory.

This example is intended to be run on an ESP32.
*/

/**
A security store that saves the TLS session state in RTC memory.

*/
class SecurityStoreRtc extends http.SecurityStore:
  // We store the cached session data in RTC memory. This means that
  // it survives deep sleeps, but that any loss of power or firmware
  // update will clear it.
  bucket_/storage.Bucket

  constructor path/string:
    bucket_ = storage.Bucket.open --ram path

  store-session-data host/string port/int data/ByteArray -> none:
    bucket_[key_ host port] = data

  delete-session-data host/string port/int -> none:
    bucket_.remove (key_ host port)

  retrieve-session-data host/string port/int -> ByteArray?:
    return bucket_.get (key_ host port)

  key_ host/string port/int -> string:
    return "$host:$port"

main:
  // Install common trusted roots.
  certificate-roots.install-common-trusted-roots
  network := net.open

  security-store := SecurityStoreRtc "toitlang.org/pkg-http/example/tls-session-store"
  client := http.Client.tls network
      --security-store=security-store

  response := null
  duration := Duration.of:
    response = client.get --uri="https://www.example.com"
  // Running this program a second time should be faster, as the TLS
  // connection could just be resumed.
  print "Took $duration to get response."

  client.close
  network.close
