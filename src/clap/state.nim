import plugin

const
    CLAP_EXT_STATE *: cstring = "clap.state"

type
    ClapIStream* = object
        ctx*: pointer
        read*: proc (stream: ptr ClapIStream, buffer: pointer, size: uint64): int64 {.cdecl.}

    ClapOStream* = object
        ctx*: pointer
        write*: proc (stream: ptr ClapOStream, buffer: pointer, size: uint64): int64 {.cdecl.}

    ClapPluginState* = object
        save*: proc (plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.}
        load*: proc (plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.}

    ClapHostState* = object
        mark_dirty*: proc (host: ptr ClapHost): void {.cdecl.}