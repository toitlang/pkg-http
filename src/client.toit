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
import .method
import .headers

class Client:
  interface_/tcp.Interface

  use_tls_ ::= false
  certificate_/tls.Certificate? ::= null
  server_name_/string? ::= null
  root_certificates_/List ::= []

  constructor .interface_:

  constructor.tls .interface_
      --root_certificates/List=[]
      --server_name/string?=null
      --certificate/tls.Certificate?=null:
    use_tls_ = true
    root_certificates_ = root_certificates
    server_name_ = server_name
    certificate_ = certificate

  new_request method/string host/string --port/int=default_port path/string --headers/Headers=Headers -> Request:
    connection := new_connection_ host port
    request := connection.new_request method path headers
    return request

  get host/string --port/int=default_port path/string --headers/Headers=Headers -> Response:
    connection := new_connection_ host port --auto_close
    request := connection.new_request GET path headers
    return request.send

  new_connection_ host/string port/int --auto_close=false -> Connection:
    index := host.index_of ":"
    if index >= 0:
      port = int.parse host[index+1..]
      host = host[..index]
    socket := interface_.tcp_connect host port
    if use_tls_:
      socket = tls.Socket.client socket
        --server_name=server_name_ or host
        --certificate=certificate_
        --root_certificates=root_certificates_
    return Connection socket --host=host --auto_close=auto_close

  default_port -> int:
    return use_tls_ ? 443 : 80
