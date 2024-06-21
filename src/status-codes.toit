// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .method // For toitdoc.

/**
The server switches protocols.

For example, the server sends this status code when it switches to websockets.
*/
STATUS-SWITCHING-PROTOCOLS ::= 101

/**
The server has received the request, and is processing it, but
  no response is available yet.
*/
STATUS-PROCESSING ::= 102

/**
Status code for the Link header. It lets the user agent start preloading resources
  while the server is still processing the request.
*/
STATUS-EARLY-HINTS ::= 103

/**
The request succeeded.

The actual meaning depends on the method that was used:
- $GET: The resource was returned in the message body.
- $HEAD: The response contains the headers, but there is no message body.
- $POST or $PUT: The result of the operation is returned in the message body.
- $TRACE: The message body contains the request message as received by the server.
*/
STATUS-OK ::= 200

/**
The request succeeded, and the server created a new resource.
*/
STATUS-CREATED ::= 201

/**
The request succeeded, and the server accepted the request, but
  has not yet processed it.
*/
STATUS-ACCEPTED ::= 202

/**
The returned metadata in the response is not the definitive set
  as available from the origin server, but is gathered from a local or a third-party
  copy.
*/
STATUS-NON-AUTHORITATIVE-INFORMATION ::= 203

/**
The server has successfully processed the request and is not returning any content.
*/
STATUS-NO-CONTENT ::= 204

/**
Status code to inform the user agent to reset the document which sent the request.
*/
STATUS-RESET-CONTENT ::= 205

/**
The server has fulfilled the partial GET request for the resource.
*/
STATUS-PARTIAL-CONTENT ::= 206

/**
The message body contains the status of multiple independent operations.
*/
STATUS-MULTI-STATUS ::= 207

/**
The members of a DAV binding have already been enumerated in a
  previous reply to this request, and are not being included again.
*/
STATUS-ALREADY-REPORTED ::= 208

/**
The server has fulfilled a request for the resource, and the response is a
  representation of the result of one or more instance-manipulations applied to the
  current instance.
*/
STATUS-IM-USED ::= 226

/**
The request has more than one possible response.
*/
STATUS-MULTIPLE-CHOICES ::= 300

/**
A resource has moved permanently.

This might be used when a web site was reorganized.

Similar to $STATUS-PERMANENT-REDIRECT, except that the method is not guaranteed
  except for $GET.

For clients the simplest is to treat $STATUS-MOVED-PERMANENTLY the same as
  $STATUS-PERMANENT-REDIRECT.

# Advanced
If the method was $GET, then the redirected target must also be retrieved with $GET.
  For other methods, the server should not assume that the redirected target is again
  retrieved with the same method. The status code $STATUS-PERMANENT-REDIRECT specifies
  that the method must not be changed.
*/
STATUS-MOVED-PERMANENTLY ::= 301

/**
The target is temporarily unavailable.

For clients the simplest is to treat $STATUS-FOUND the same as
  $STATUS-TEMPORARY-REDIRECT.

# Advanced
If the method was $GET, then the redirected target must also be retrieved with $GET.
  For other methods, the server should not assume that the redirected target is again
  retrieved with the same method. The status code $STATUS-TEMPORARY-REDIRECT specifies
  that the method must not be changed.
*/
STATUS-FOUND ::= 302

/**
The client is redirected to a $GET target.

This is typically used to redirect after a $PUT or $POST, so that refreshing the
  result page doesn't resubmit data.
*/
STATUS-SEE-OTHER ::= 303

/**
The target is temporarily unavailable.

The method ($GET, $POST, ...) must be the same when accessing the redirection target.
*/
STATUS-TEMPORARY-REDIRECT ::= 307

/**
A resource has moved permanently.

This might be used when a web site was reorganized.

Search engine robots, RSS readers, and similar tools should update the original URL

The method ($GET, $POST, ...) must be the same when accessing the redirection target.
*/
STATUS-PERMANENT-REDIRECT ::= 308

/**
A malformed request.
*/
STATUS-BAD-REQUEST ::= 400

/**
The user is not authorized to access the resource.
*/
STATUS-UNAUTHORIZED ::= 401

/**
Reserved for future use.
*/
STATUS-PAYMENT-REQUIRED ::= 402

/**
The client does not have access rights to the content.
*/
STATUS-FORBIDDEN ::= 403

/**
The server can not find the requested resource.
*/
STATUS-NOT-FOUND ::= 404

/**
The method is not allowed for the requested resource.
*/
STATUS-METHOD-NOT-ALLOWED ::= 405

/**
The request is not acceptable.

This happens when the server doesn't find any acceptable content after
  server-driven content negotiation.
*/
STATUS-NOT-ACCEPTABLE ::= 406

/**
The client must first authenticate itself with the proxy.
*/
STATUS-PROXY-AUTHENTICATION-REQUIRED ::= 407

/**
The server timed out waiting for the request.
*/
STATUS-REQUEST-TIMEOUT ::= 408

/**
The request could not be completed because of a conflict in the request.
*/
STATUS-CONFLICT ::= 409

/**
The requested resource is no longer available at the server and no forwarding address
  is known.
*/
STATUS-GONE ::= 410

/**
The server refuses to accept the request without a defined Content-Length.
*/
STATUS-LENGTH-REQUIRED ::= 411

/**
The precondition given in one or more of the request-header fields evaluated to false
  when it was tested on the server.
*/
STATUS-PRECONDITION-FAILED ::= 412

/**
The payload is too big.
*/
STATUS-PAYLOAD-TOO-LARGE ::= 413

/**
The URI is too long.
*/
STATUS-REQUEST-URI-TOO-LONG ::= 414

/**
The request entity has a media type which the server or resource does not support.
*/
STATUS-UNSUPPORTED-MEDIA-TYPE ::= 415

/**
The client has asked for a portion of the file, but the server cannot supply that
  portion.
*/
STATUS-REQUESTED-RANGE-NOT-SATISFIABLE ::= 416

/**
The server cannot meet the requirements of the Expect request-header field.
*/
STATUS-EXPECTATION-FAILED ::= 417

/**
The server refuses the attempt to brew coffee with a teapot.

This might be returned by a server that does not wish to reveal exactly why the
  request has been refused, or when no other response is applicable.

This status code originates from an April fool's joke in RFC 2324, and is not expected
  to be implemented by actual HTTP servers.
*/
STATUS-IM-A-TEAPOT ::= 418

/**
The request was directed at a server that is not able to produce a response.
*/
STATUS-MISDIRECTED-REQUEST ::= 421

/**
The request was well-formed but was unable to be followed due to semantic errors.
*/
STATUS-UNPROCESSABLE-ENTITY ::= 422

/**
The resource that is being accessed is locked.
*/
STATUS-LOCKED ::= 423

/**
The request failed due to failure of a previous request.
*/
STATUS-FAILED-DEPENDENCY ::= 424

/**
The server is unwilling to process a request that could be a replay of a previous
  request.
*/
STATUS-TOO-EARLY ::= 425

/**
The server refuses to perform the request using the current protocol but might be
  willing to do so after the client upgrades to a different protocol.
*/
STATUS-UPGRADE-REQUIRED ::= 426

/**
The origin server requires the request to be conditional.
*/
STATUS-PRECONDITION-REQUIRED ::= 428

/**
The user has sent too many requests in a given amount of time.
*/
STATUS-TOO-MANY-REQUESTS ::= 429

/**
The request's header fields are too large.
*/
STATUS-REQUEST-HEADER-FIELDS-TOO-LARGE ::= 431

/**
The server can't fulfill the request because of legal reasons.
*/
STATUS-UNAVAILABLE-FOR-LEGAL-REASONS ::= 451

/**
The server encountered an unexpected condition that prevented it from fulfilling the
  request.
*/
STATUS-INTERNAL-SERVER-ERROR ::= 500

/**
The method is not supported by the server.
*/
STATUS-NOT-IMPLEMENTED ::= 501

/**
The server, while working as a gateway, was unable to get a response
  needed to handle the request.
*/
STATUS-BAD-GATEWAY ::= 502

/**
The server is not able to handle the request.
*/
STATUS-SERVICE-UNAVAILABLE ::= 503

/**
The server, while acting as a gateway, did not receive a timely response
  from the upstream server.
*/
STATUS-GATEWAY-TIMEOUT ::= 504

/**
The server does not support the HTTP protocol version used in the request.
*/
STATUS-HTTP-VERSION-NOT-SUPPORTED ::= 505

/**
The server has an internal configuration error: transparent content negotiation
  for the request results in a circular reference.
*/
STATUS-VARIANT-ALSO-NEGOTIATES ::= 506

/**
The server is unable to store the representation needed to complete the request.
*/
STATUS-INSUFFICIENT-STORAGE ::= 507

/**
The server detected an infinite loop while processing the request.
*/
STATUS-LOOP-DETECTED ::= 508

/**
One of the requested extensions is not supported by the server.
*/
STATUS-NOT-EXTENDED ::= 510

/**
Status codes for close packets on the Websockets protocol.
*/
STATUS-WEBSOCKET-NORMAL-CLOSURE       ::= 1000
STATUS-WEBSOCKET-GOING-AWAY           ::= 1001
STATUS-WEBSOCKET-PROTOCOL-ERROR       ::= 1002
STATUS-WEBSOCKET-NOT-UNDERSTOOD       ::= 1003
STATUS-WEBSOCKET-RESERVED             ::= 1004
STATUS-WEBSOCKET-NO-STATUS-CODE       ::= 1005
STATUS-WEBSOCKET-CONNECTION-CLOSED    ::= 1006
STATUS-WEBSOCKET-INCONSISTENT-DATA_   ::= 1007
STATUS-WEBSOCKET-POLICY-VIOLATION     ::= 1008
STATUS-WEBSOCKET-MESSAGE-TOO-BIG      ::= 1009
STATUS-WEBSOCKET-MISSING-EXTENSION    ::= 1010
STATUS-WEBSOCKET-UNEXPECTED-CONDITION ::= 1011
STATUS-WEBSOCKET-TLS-FAILURE          ::= 1015

/**
The client needs to authenticate.
*/
STATUS-NETWORK-AUTHENTICATION-REQUIRED ::= 511

status-messages_/Map ::= {
  STATUS-SWITCHING-PROTOCOLS: "Switching Protocols",
  STATUS-PROCESSING: "Processing",
  STATUS-EARLY-HINTS: "Early Hints",

  STATUS-OK: "OK",
  STATUS-CREATED: "Created",
  STATUS-ACCEPTED: "Accepted",
  STATUS-NON-AUTHORITATIVE-INFORMATION: "Non-Authoritative Information",
  STATUS-NO-CONTENT: "No Content",
  STATUS-RESET-CONTENT: "Reset Content",
  STATUS-PARTIAL-CONTENT: "Partial Content",
  STATUS-ALREADY-REPORTED: "Already Reported",
  STATUS-IM-USED: "IM Used",

  STATUS-MULTIPLE-CHOICES: "Multiple Choices",
  STATUS-MOVED-PERMANENTLY: "Moved Permanently",
  STATUS-FOUND: "Found",
  STATUS-SEE-OTHER: "See Other",
  STATUS-TEMPORARY-REDIRECT: "Temporary Redirect",
  STATUS-PERMANENT-REDIRECT: "Permanent Redirect",

  STATUS-BAD-REQUEST: "Bad Request",
  STATUS-UNAUTHORIZED: "Unauthorized",
  STATUS-PAYMENT-REQUIRED: "Payment Required",
  STATUS-FORBIDDEN: "Forbidden",
  STATUS-NOT-FOUND: "Not Found",
  STATUS-METHOD-NOT-ALLOWED: "Method Not Allowed",
  STATUS-NOT-ACCEPTABLE: "Not Acceptable",
  STATUS-PROXY-AUTHENTICATION-REQUIRED: "Proxy Authentication Required",
  STATUS-REQUEST-TIMEOUT: "Request Timeout",
  STATUS-CONFLICT: "Conflict",
  STATUS-GONE: "Gone",
  STATUS-LENGTH-REQUIRED: "Length Required",
  STATUS-PRECONDITION-FAILED: "Precondition Failed",
  STATUS-PAYLOAD-TOO-LARGE: "Payload Too Large",
  STATUS-REQUEST-URI-TOO-LONG: "Request-URI Too Long",
  STATUS-UNSUPPORTED-MEDIA-TYPE: "Unsupported Media Type",
  STATUS-REQUESTED-RANGE-NOT-SATISFIABLE: "Requested Range Not Satisfiable",
  STATUS-EXPECTATION-FAILED: "Expectation Failed",
  STATUS-IM-A-TEAPOT: "I'm a teapot",
  STATUS-MISDIRECTED-REQUEST: "Misdirected Request",
  STATUS-UNPROCESSABLE-ENTITY: "Unprocessable Entity",
  STATUS-LOCKED: "Locked",
  STATUS-FAILED-DEPENDENCY: "Failed Dependency",
  STATUS-TOO-EARLY: "Too Early",
  STATUS-UPGRADE-REQUIRED: "Upgrade Required",
  STATUS-PRECONDITION-REQUIRED: "Precondition Required",
  STATUS-TOO-MANY-REQUESTS: "Too Many Requests",
  STATUS-REQUEST-HEADER-FIELDS-TOO-LARGE: "Request Header Fields Too Large",
  STATUS-UNAVAILABLE-FOR-LEGAL-REASONS: "Unavailable For Legal Reasons",

  STATUS-INTERNAL-SERVER-ERROR: "Internal Server Error",
  STATUS-NOT-IMPLEMENTED: "Not Implemented",
  STATUS-BAD-GATEWAY: "Bad Gateway",
  STATUS-SERVICE-UNAVAILABLE: "Service Unavailable",
  STATUS-GATEWAY-TIMEOUT: "Gateway Timeout",
  STATUS-HTTP-VERSION-NOT-SUPPORTED: "HTTP Version Not Supported",
  STATUS-VARIANT-ALSO-NEGOTIATES: "Variant Also Negotiates",
  STATUS-INSUFFICIENT-STORAGE: "Insufficient Storage",
  STATUS-LOOP-DETECTED: "Loop Detected",
  STATUS-NOT-EXTENDED: "Not Extended",
  STATUS-NETWORK-AUTHENTICATION-REQUIRED: "Network Authentication Required",
}

status-message status-code/int -> string:
  return status-messages_.get status-code
    --if-absent=: ""


is-regular-redirect_ status-code/int -> bool:
  return status-code == STATUS-MOVED-PERMANENTLY
      or status-code == STATUS-FOUND
      or status-code == STATUS-TEMPORARY-REDIRECT
      or status-code == STATUS-PERMANENT-REDIRECT

is-information-status-code status-code/int -> bool:
  return 100 <= status-code < 200

is-success-status-code status-code/int -> bool:
  return 200 <= status-code < 300

is-redirect-status-code status-code/int -> bool:
  return 300 <= status-code < 400

is-client-error-status-code status-code/int -> bool:
  return 400 <= status-code < 500

is-server-error-status-code status-code/int -> bool:
  return 500 <= status-code < 600
