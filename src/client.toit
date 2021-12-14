// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import net
import net.tcp
import reader
import tls

import .request
import .response
import .connection
import .tls_config

class Client:
  interface_/tcp.Interface
  tls_config/TlsConfig?

  constructor .interface_ --.tls_config=null:

  get host/string path/string -> Response:
    connection := new_connection_ host --auto_close
    request := connection.new_request "GET" path
    return request.send

  new_connection_ host/string --auto_close=false -> Connection:
    port := 80
    index := host.index_of ":"
    if index >= 0:
      port = int.parse host[index+1..]
      host = host[..index]
    socket := interface_.tcp_connect host port
    if tls_config:
      socket = tls.Socket.client socket
        --server_name=tls_config.server_name or host
        --certificate=tls_config.certificate
        --root_certificates=tls_config.root_certificates
    return Connection socket --host=host --auto_close=auto_close
