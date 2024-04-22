// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .method // For toitdoc.

/**
The server switches protocols.

For example, the server sends this status code when it switches to websockets.
*/
STATUS_SWITCHING_PROTOCOLS ::= 101

/**
The server has received the request, and is processing it, but
  no response is available yet.
*/
STATUS_PROCESSING ::= 102

/**
Status code for the Link header. It lets the user agent start preloading resources
  while the server is still processing the request.
*/
STATUS_EARLY_HINTS ::= 103

/**
The request succeeded.

The actual meaning depends on the method that was used:
- $GET: The resource was returned in the message body.
- $HEAD: The response contains the headers, but there is no message body.
- $POST or $PUT: The result of the operation is returned in the message body.
- $TRACE: The message body contains the request message as received by the server.
*/
STATUS_OK ::= 200

/**
The request succeeded, and the server created a new resource.
*/
STATUS_CREATED ::= 201

/**
The request succeeded, and the server accepted the request, but
  has not yet processed it.
*/
STATUS_ACCEPTED ::= 202

/**
The returned metadata in the response is not the definitive set
  as available from the origin server, but is gathered from a local or a third-party
  copy.
*/
STATUS_NON_AUTHORITATIVE_INFORMATION ::= 203

/**
The server has successfully processed the request and is not returning any content.
*/
STATUS_NO_CONTENT ::= 204

/**
Status code to inform the user agent to reset the document which sent the request.
*/
STATUS_RESET_CONTENT ::= 205

/**
The server has fulfilled the partial GET request for the resource.
*/
STATUS_PARTIAL_CONTENT ::= 206

/**
The message body contains the status of multiple independent operations.
*/
STATUS_MULTI_STATUS ::= 207

/**
The members of a DAV binding have already been enumerated in a
  previous reply to this request, and are not being included again.
*/
STATUS_ALREADY_REPORTED ::= 208

/**
The server has fulfilled a request for the resource, and the response is a
  representation of the result of one or more instance-manipulations applied to the
  current instance.
*/
STATUS_IM_USED ::= 226

/**
The request has more than one possible response.
*/
STATUS_MULTIPLE_CHOICES ::= 300

/**
A resource has moved permanently.

This might be used when a web site was reorganized.

Similar to $STATUS_PERMANENT_REDIRECT, except that the method is not guaranteed
  except for $GET.

For clients the simplest is to treat $STATUS_MOVED_PERMANENTLY the same as
  $STATUS_PERMANENT_REDIRECT.

# Advanced
If the method was $GET, then the redirected target must also be retrieved with $GET.
  For other methods, the server should not assume that the redirected target is again
  retrieved with the same method. The status code $STATUS_PERMANENT_REDIRECT specifies
  that the method must not be changed.
*/
STATUS_MOVED_PERMANENTLY ::= 301

/**
The target is temporarily unavailable.

For clients the simplest is to treat $STATUS_FOUND the same as
  $STATUS_TEMPORARY_REDIRECT.

# Advanced
If the method was $GET, then the redirected target must also be retrieved with $GET.
  For other methods, the server should not assume that the redirected target is again
  retrieved with the same method. The status code $STATUS_TEMPORARY_REDIRECT specifies
  that the method must not be changed.
*/
STATUS_FOUND ::= 302

/**
The client is redirected to a $GET target.

This is typically used to redirect after a $PUT or $POST, so that refreshing the
  result page doesn't resubmit data.
*/
STATUS_SEE_OTHER ::= 303

/**
The target is temporarily unavailable.

The method ($GET, $POST, ...) must be the same when accessing the redirection target.
*/
STATUS_TEMPORARY_REDIRECT ::= 307

/**
A resource has moved permanently.

This might be used when a web site was reorganized.

Search engine robots, RSS readers, and similar tools should update the original URL

The method ($GET, $POST, ...) must be the same when accessing the redirection target.
*/
STATUS_PERMANENT_REDIRECT ::= 308

/**
A malformed request.
*/
STATUS_BAD_REQUEST ::= 400

/**
The user is not authorized to access the resource.
*/
STATUS_UNAUTHORIZED ::= 401

/**
Reserved for future use.
*/
STATUS_PAYMENT_REQUIRED ::= 402

/**
The client does not have access rights to the content.
*/
STATUS_FORBIDDEN ::= 403

/**
The server can not find the requested resource.
*/
STATUS_NOT_FOUND ::= 404

/**
The method is not allowed for the requested resource.
*/
STATUS_METHOD_NOT_ALLOWED ::= 405

/**
The request is not acceptable.

This happens when the server doesn't find any acceptable content after
  server-driven content negotiation.
*/
STATUS_NOT_ACCEPTABLE ::= 406

/**
The client must first authenticate itself with the proxy.
*/
STATUS_PROXY_AUTHENTICATION_REQUIRED ::= 407

/**
The server timed out waiting for the request.
*/
STATUS_REQUEST_TIMEOUT ::= 408

/**
The request could not be completed because of a conflict in the request.
*/
STATUS_CONFLICT ::= 409

/**
The requested resource is no longer available at the server and no forwarding address
  is known.
*/
STATUS_GONE ::= 410

/**
The server refuses to accept the request without a defined Content-Length.
*/
STATUS_LENGTH_REQUIRED ::= 411

/**
The precondition given in one or more of the request-header fields evaluated to false
  when it was tested on the server.
*/
STATUS_PRECONDITION_FAILED ::= 412

/**
The payload is too big.
*/
STATUS_PAYLOAD_TOO_LARGE ::= 413

/**
The URI is too long.
*/
STATUS_REQUEST_URI_TOO_LONG ::= 414

/**
The request entity has a media type which the server or resource does not support.
*/
STATUS_UNSUPPORTED_MEDIA_TYPE ::= 415

/**
The client has asked for a portion of the file, but the server cannot supply that
  portion.
*/
STATUS_REQUESTED_RANGE_NOT_SATISFIABLE ::= 416

/**
The server cannot meet the requirements of the Expect request-header field.
*/
STATUS_EXPECTATION_FAILED ::= 417

/**
The server refuses the attempt to brew coffee with a teapot.

This might be returned by a server that does not wish to reveal exactly why the
  request has been refused, or when no other response is applicable.

This status code originates from an April fool's joke in RFC 2324, and is not expected
  to be implemented by actual HTTP servers.
*/
STATUS_IM_A_TEAPOT ::= 418

/**
The request was directed at a server that is not able to produce a response.
*/
STATUS_MISDIRECTED_REQUEST ::= 421

/**
The request was well-formed but was unable to be followed due to semantic errors.
*/
STATUS_UNPROCESSABLE_ENTITY ::= 422

/**
The resource that is being accessed is locked.
*/
STATUS_LOCKED ::= 423

/**
The request failed due to failure of a previous request.
*/
STATUS_FAILED_DEPENDENCY ::= 424

/**
The server is unwilling to process a request that could be a replay of a previous
  request.
*/
STATUS_TOO_EARLY ::= 425

/**
The server refuses to perform the request using the current protocol but might be
  willing to do so after the client upgrades to a different protocol.
*/
STATUS_UPGRADE_REQUIRED ::= 426

/**
The origin server requires the request to be conditional.
*/
STATUS_PRECONDITION_REQUIRED ::= 428

/**
The user has sent too many requests in a given amount of time.
*/
STATUS_TOO_MANY_REQUESTS ::= 429

/**
The request's header fields are too large.
*/
STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE ::= 431

/**
The server can't fulfill the request because of legal reasons.
*/
STATUS_UNAVAILABLE_FOR_LEGAL_REASONS ::= 451

/**
The server encountered an unexpected condition that prevented it from fulfilling the
  request.
*/
STATUS_INTERNAL_SERVER_ERROR ::= 500

/**
The method is not supported by the server.
*/
STATUS_NOT_IMPLEMENTED ::= 501

/**
The server, while working as a gateway, was unable to get a response
  needed to handle the request.
*/
STATUS_BAD_GATEWAY ::= 502

/**
The server is not able to handle the request.
*/
STATUS_SERVICE_UNAVAILABLE ::= 503

/**
The server, while acting as a gateway, did not receive a timely response
  from the upstream server.
*/
STATUS_GATEWAY_TIMEOUT ::= 504

/**
The server does not support the HTTP protocol version used in the request.
*/
STATUS_HTTP_VERSION_NOT_SUPPORTED ::= 505

/**
The server has an internal configuration error: transparent content negotiation
  for the request results in a circular reference.
*/
STATUS_VARIANT_ALSO_NEGOTIATES ::= 506

/**
The server is unable to store the representation needed to complete the request.
*/
STATUS_INSUFFICIENT_STORAGE ::= 507

/**
The server detected an infinite loop while processing the request.
*/
STATUS_LOOP_DETECTED ::= 508

/**
One of the requested extensions is not supported by the server.
*/
STATUS_NOT_EXTENDED ::= 510

/**
Status codes for close packets on the Websockets protocol.
*/
STATUS_WEBSOCKET_NORMAL_CLOSURE       ::= 1000
STATUS_WEBSOCKET_GOING_AWAY           ::= 1001
STATUS_WEBSOCKET_PROTOCOL_ERROR       ::= 1002
STATUS_WEBSOCKET_NOT_UNDERSTOOD       ::= 1003
STATUS_WEBSOCKET_RESERVED             ::= 1004
STATUS_WEBSOCKET_NO_STATUS_CODE       ::= 1005
STATUS_WEBSOCKET_CONNECTION_CLOSED    ::= 1006
STATUS_WEBSOCKET_INCONSISTENT_DATA_   ::= 1007
STATUS_WEBSOCKET_POLICY_VIOLATION     ::= 1008
STATUS_WEBSOCKET_MESSAGE_TOO_BIG      ::= 1009
STATUS_WEBSOCKET_MISSING_EXTENSION    ::= 1010
STATUS_WEBSOCKET_UNEXPECTED_CONDITION ::= 1011
STATUS_WEBSOCKET_TLS_FAILURE          ::= 1015

/**
The client needs to authenticate.
*/
STATUS_NETWORK_AUTHENTICATION_REQUIRED ::= 511

status_messages_/Map ::= {
  STATUS_SWITCHING_PROTOCOLS: "Switching Protocols",
  STATUS_PROCESSING: "Processing",
  STATUS_EARLY_HINTS: "Early Hints",

  STATUS_OK: "OK",
  STATUS_CREATED: "Created",
  STATUS_ACCEPTED: "Accepted",
  STATUS_NON_AUTHORITATIVE_INFORMATION: "Non-Authoritative Information",
  STATUS_NO_CONTENT: "No Content",
  STATUS_RESET_CONTENT: "Reset Content",
  STATUS_PARTIAL_CONTENT: "Partial Content",
  STATUS_ALREADY_REPORTED: "Already Reported",
  STATUS_IM_USED: "IM Used",

  STATUS_MULTIPLE_CHOICES: "Multiple Choices",
  STATUS_MOVED_PERMANENTLY: "Moved Permanently",
  STATUS_FOUND: "Found",
  STATUS_SEE_OTHER: "See Other",
  STATUS_TEMPORARY_REDIRECT: "Temporary Redirect",
  STATUS_PERMANENT_REDIRECT: "Permanent Redirect",

  STATUS_BAD_REQUEST: "Bad Request",
  STATUS_UNAUTHORIZED: "Unauthorized",
  STATUS_PAYMENT_REQUIRED: "Payment Required",
  STATUS_FORBIDDEN: "Forbidden",
  STATUS_NOT_FOUND: "Not Found",
  STATUS_METHOD_NOT_ALLOWED: "Method Not Allowed",
  STATUS_NOT_ACCEPTABLE: "Not Acceptable",
  STATUS_PROXY_AUTHENTICATION_REQUIRED: "Proxy Authentication Required",
  STATUS_REQUEST_TIMEOUT: "Request Timeout",
  STATUS_CONFLICT: "Conflict",
  STATUS_GONE: "Gone",
  STATUS_LENGTH_REQUIRED: "Length Required",
  STATUS_PRECONDITION_FAILED: "Precondition Failed",
  STATUS_PAYLOAD_TOO_LARGE: "Payload Too Large",
  STATUS_REQUEST_URI_TOO_LONG: "Request-URI Too Long",
  STATUS_UNSUPPORTED_MEDIA_TYPE: "Unsupported Media Type",
  STATUS_REQUESTED_RANGE_NOT_SATISFIABLE: "Requested Range Not Satisfiable",
  STATUS_EXPECTATION_FAILED: "Expectation Failed",
  STATUS_IM_A_TEAPOT: "I'm a teapot",
  STATUS_MISDIRECTED_REQUEST: "Misdirected Request",
  STATUS_UNPROCESSABLE_ENTITY: "Unprocessable Entity",
  STATUS_LOCKED: "Locked",
  STATUS_FAILED_DEPENDENCY: "Failed Dependency",
  STATUS_TOO_EARLY: "Too Early",
  STATUS_UPGRADE_REQUIRED: "Upgrade Required",
  STATUS_PRECONDITION_REQUIRED: "Precondition Required",
  STATUS_TOO_MANY_REQUESTS: "Too Many Requests",
  STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE: "Request Header Fields Too Large",
  STATUS_UNAVAILABLE_FOR_LEGAL_REASONS: "Unavailable For Legal Reasons",

  STATUS_INTERNAL_SERVER_ERROR: "Internal Server Error",
  STATUS_NOT_IMPLEMENTED: "Not Implemented",
  STATUS_BAD_GATEWAY: "Bad Gateway",
  STATUS_SERVICE_UNAVAILABLE: "Service Unavailable",
  STATUS_GATEWAY_TIMEOUT: "Gateway Timeout",
  STATUS_HTTP_VERSION_NOT_SUPPORTED: "HTTP Version Not Supported",
  STATUS_VARIANT_ALSO_NEGOTIATES: "Variant Also Negotiates",
  STATUS_INSUFFICIENT_STORAGE: "Insufficient Storage",
  STATUS_LOOP_DETECTED: "Loop Detected",
  STATUS_NOT_EXTENDED: "Not Extended",
  STATUS_NETWORK_AUTHENTICATION_REQUIRED: "Network Authentication Required",
}

status_message status_code/int -> string:
  return status_messages_.get status_code
    --if_absent=: ""


is_regular_redirect_ status_code/int -> bool:
  return status_code == STATUS_MOVED_PERMANENTLY
      or status_code == STATUS_FOUND
      or status_code == STATUS_TEMPORARY_REDIRECT
      or status_code == STATUS_PERMANENT_REDIRECT

is_information_status_code status_code/int -> bool:
  return 100 <= status_code < 200

is_success_status_code status_code/int -> bool:
  return 200 <= status_code < 300

is_redirect_status_code status_code/int -> bool:
  return 300 <= status_code < 400

is_client_error_status_code status_code/int -> bool:
  return 400 <= status_code < 500

is_server_error_status_code status_code/int -> bool:
  return 500 <= status_code < 600
