// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import tls

import .client
import .server

/**
TlsConfig used when communicating over HTTPS instead of HTTP.

The config should be initialized either for the server or the client.
*/
class TlsConfig:
  certificate/tls.Certificate?
  server_name/string? ::= null
  root_certificates/List ::= []

  /**
  Initializes the config to be used together with a $Client.
  */
  constructor.client
      --.root_certificates=[]
      --.server_name=null
      --.certificate=null:

  /**
  Initializes the config to be used together with a $Server.
  */
  constructor.server .certificate/tls.Certificate
      --.root_certificates=[]:
