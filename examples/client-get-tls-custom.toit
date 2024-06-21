// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import http
import net
import net.x509

main:
  network := net.open
  client := http.Client.tls network
    --root-certificates=[SERVER-CERT]

  response := client.get "localhost:8080" "/json"
  while data := response.body.read:
    print data.to-string

  client.close

SERVER-CERT ::= x509.Certificate.parse """
-----BEGIN CERTIFICATE-----
MIIDkzCCAnugAwIBAgIUb3nSgGzXBdgsDhg8shods8EHszAwDQYJKoZIhvcNAQEL
BQAwWTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoM
GEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDESMBAGA1UEAwwJbG9jYWxob3N0MB4X
DTIxMTIxNDExNDUzNVoXDTIyMTIxNDExNDUzNVowWTELMAkGA1UEBhMCQVUxEzAR
BgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoMGEludGVybmV0IFdpZGdpdHMgUHR5
IEx0ZDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
MIIBCgKCAQEAtLgY3fcm1/HIRPnAH7rsWfyH4bWstTP1LXIM1Z31vv3cYNygzt2m
Njoh2JAeS64Ut403Ms4Ts0tO0SdwfSPX7Bc3gwhdtAWjlMgmk49ip/v5fSSupty9
3xGRHV7OMrOW7I5sORIpgFomHTD8GD0NjccCcAnP9gFbIJNS2bny5XdcTsbiImE/
Yew/lGZmal103DBPAM1HqOHCbcvXoKpB9Wm6/2ea2fHR/rLrl0e686q9bJlIqkRu
/e8ll+fVhSSpTZ6HfE7+/gMfD7VrF28RZYgHZ6KQmvaPHDSfYHUM9ueI9UtER0D8
qs0sZf+6MvCbWmHDpiPuV8x8DlIZbVXe+QIDAQABo1MwUTAdBgNVHQ4EFgQUCS0N
6qxa+6k20iqeoDCPdqU2m+wwHwYDVR0jBBgwFoAUCS0N6qxa+6k20iqeoDCPdqU2
m+wwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAOG9LbUNBUy9o
82k9nsPPWMsZxK4p1NvAvwAFEOKmmvZ3Ix/LreoKN0+Yqm22M4MJzlduI6gULo6e
cPx9cdKl7gYCAecp15QGCydFYl0fGnYc8YR0XihjtKIYpnbiy0WdWXlX+U67oFun
n776Ths/vajhB/xWScZgFILOF8WP7wjh4oDTlD1lwVsVZDcEVL6mHSzFOKBkWkS7
ehkVn8k6vUedKEId2GvmBtuM7bZ3P7BcNo9YGf2xK6Ik3w6NujbWGtO63Dm3gHBd
ysgaN/Q+Nir6Y9uxVmmTqP2zTpNT0jt1q9TlKjm1/omU8ASi2SvCIR/rCH2OFrRY
eLYDrha/bg==
-----END CERTIFICATE-----
"""
