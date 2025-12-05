when defined(grpcTls):
    {.hint: "grpcTls is defined, define ssl to enable TLS support".}
    {.define: ssl.}
    import std/[net, openssl, asyncnet]
    export net, openssl, asyncnet

import std/[json, tables, options, os, asyncdispatch, sequtils, sugar]
import nimproto3/[ast, parser, codegen, codegen_macro, wire_format, grpc]

export ast, parser, codegen, codegen_macro, wire_format, json, tables, grpc,
    options, os, asyncdispatch, sequtils, sugar

