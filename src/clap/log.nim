import plugin

const
    CLAP_EXT_LOG *: cstring = "clap.log"

type
    ClapLogSeverity* {.size:sizeof(int32).} = enum
        clsDEBUG              = 0,
        clsINFO               = 1,
        clsWARNING            = 2,
        clsERROR              = 3,
        clsFATAL              = 4,
        clsHOST_MISBEHAVING   = 5,
        clsPLUGIN_MISBEHAVING = 6

    ClapHostLog* = ClapHostLogT
    ClapHostLogT* = object
        # Log a message through the host.
        log*: proc (host: ptr ClapHost, severity: ClapLogSeverity, msg: cstring): void {.cdecl.}

    ClapHostThreadCheck* = ClapHostThreadCheckT
    ClapHostThreadCheckT* = object
        is_main_thread  *: proc (host: ptr ClapHost): bool {.cdecl.}
        is_audio_thread *: proc (host: ptr ClapHost): bool {.cdecl.}