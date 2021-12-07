
// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import net
import net.tcp
import reader

import .request
import .response
import .connection

class SingleReader implements reader.Reader:
  data/any := ?
  constructor .data:
  read:
    d := data
    data = null
    return d

class Client:
  interface_/tcp.Interface

  constructor .interface_:

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
    return Connection socket --host=host --auto_close=auto_close
