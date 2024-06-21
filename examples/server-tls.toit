// Copyright (C) 2021 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import net.x509
import http
import encoding.json
import net
import net.tcp
import tls

ITEMS := ["FOO", "BAR", "BAZ"]

main:
  network := net.open
  server := http.Server.tls --certificate=TLS-SERVER-CERT
  server.listen network 8080:: | request/http.RequestIncoming writer/http.ResponseWriter |
    if request.path == "/empty":
    else if request.path == "/json":
      writer.headers.set "Content-Type" "application/json"
      writer.out.write
        json.encode ITEMS
    else if request.path == "/headers":
      writer.headers.set "Http-Test-Header" "going strong"
      writer.headers.set "Content-Type" "text/plain"
      writer.out.write "hello\n"
    else if request.path == "/500":
      writer.headers.set "Content-Type" "text/plain"
      writer.write-headers 500
      writer.out.write "hello\n"
    else if request.path == "/599":
      writer.headers.set "Content-Type" "text/plain"
      writer.write-headers 599 --message="Dazed and confused"
    writer.close

// Self-signed certificate with "localhost" Common-Name.
TLS-SERVER-CERT ::= tls.Certificate SERVER-CERT SERVER-KEY

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

SERVER-KEY ::= """
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC0uBjd9ybX8chE
+cAfuuxZ/Ifhtay1M/UtcgzVnfW+/dxg3KDO3aY2OiHYkB5LrhS3jTcyzhOzS07R
J3B9I9fsFzeDCF20BaOUyCaTj2Kn+/l9JK6m3L3fEZEdXs4ys5bsjmw5EimAWiYd
MPwYPQ2NxwJwCc/2AVsgk1LZufLld1xOxuIiYT9h7D+UZmZqXXTcME8AzUeo4cJt
y9egqkH1abr/Z5rZ8dH+suuXR7rzqr1smUiqRG797yWX59WFJKlNnod8Tv7+Ax8P
tWsXbxFliAdnopCa9o8cNJ9gdQz254j1S0RHQPyqzSxl/7oy8JtaYcOmI+5XzHwO
UhltVd75AgMBAAECggEAOCrzx6E2WG2UUiPRm8sMBJfhX7yIdjU04bAN3yLeK0NZ
iF1qOYFYVIhS1q1MTTdIxxfD7S1xoAsq7wS0CKDoTj+VCEvEW9xY0Dg5DSnGfvFo
xIVvJvt6o+cg1CEQM1/v64wEhORpM7RRHkeIQrxPBx6wWkQid5JKUWCYooURwlGF
tvv5ZpC2Qzi5rEqLGMrC+ZAXMWg/rQk+1LMhCGtSPn0r8a0fBntNu3IYBJNT/cyN
E0SwvvEX9VLkgBHK4bNI1AmBjlPFdsAuP5tXxf/ncNGHhqxp5PJxSaxBaWhEhtqC
BpQKESwbgl5n1Z7yW9O2SoC7pMyhg0M24867LFJnkQKBgQDnXRufGMDLs7y4phR3
QiqqlPGp6arT9lNgEEMieDToQPRWBejQ/QvZ5jZfWl+6b0QrWSGvTDgKNxSuFa2s
E8UpjSns/2qXAAQ7dnX/vUStCvZrswmM3/sO/9tr76O9mnNXRh6uxQ2q+TwH/PYy
cm3PJwMEytVN/s3YLltLHDD+lQKBgQDH9m+r7KF1oRo2fqmEPF8749e3Dng3OotR
vQomaj+AELDWEH59msLAJUIGWpmyDYZLS2+bB+8F8fBTMyuIgH2K8ih+/axxaWUK
8INoeEUxu57DQTkgESUsYWdGswSWuK2k+6zr6WhcTsUiTGwgnvDK1zH53q87yp0o
7umPMv+Z1QKBgCizV22YhCoRl2yAQu9r42eYxh6W7adWGPq4QacpsFz/ODx906QY
L+KIPh5uHpMEieB6UJOu+9jIMcoiJCg2XiPeInb/w7eGmDgBseZoXFF4sTrnBxIS
QO81kVsekBaFui6rNjCWl73xFF9vX7wmJy0e9sf8CqQq4/lYxlSjQ/c1AoGAZvw0
DW7ExUlgr7pSYgmZ3sV8vwnTvlYHlORwitJju/hcqxM5okUHkmBd/dnBmKNAjBzg
8Q6H+x7c8GzFOfs7LUmEs8rAenSWlqjCdRakRHXl0ZgQ7MQHyjCsOQxQC7Q3smXw
bFv85LWo7/4+Hhrd1wo38gHPbFLw2DkbzyWr4LUCgYEAveTYMK3RkivlrJhc8+Yy
rFt3004S8ri803xGKO2E4pHwgmU3Yv1TSgnNSM5JEy3s+Q+5JCYvh/qSAqdbF+VT
X7bvYdD8djhHZWHFRlGYh9qdILV/javb5w3j0OEl88pSq1ZMAnd6MR3UlOl+orQb
+JJpWaWCAaNvMMxWwfiJkKk=
-----END PRIVATE KEY-----
"""
