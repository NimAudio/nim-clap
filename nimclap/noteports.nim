import shared, process

const
    CLAP_EXT_NOTE_PORTS *: cstring = "clap.note-ports"

type
    ClapNoteDialectFlag* {.size:sizeof(uint32).} = enum
        cndCLAP,
        cndMIDI,
        cndMIDI_MPE,
        cndMIDI2
    ClapNoteDialectFlags* = set[ClapNoteDialectFlag]

    ClapNotePortInfo* = ClapNotePortInfoT
    ClapNotePortInfoT* = object
        id                 *: ClapID
        supported_dialects *: ClapNoteDialectFlags
        preferred_dialect  *: ClapNoteDialectFlags
        name               *: array[CLAP_NAME_SIZE, char]

    ClapPluginNotePorts* = ClapPluginNotePortsT
    ClapPluginNotePortsT* = object
        count *: proc (plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.}
        get   *: proc (plugin: ptr ClapPlugin,
                        index: uint32,
                        is_input: bool,
                        info: ptr ClapNotePortInfo): bool {.cdecl.}

    ClapNotePortRescanFlag* {.size:sizeof(uint32).} = enum
        cnprALL,
        cnprNAMES
    ClapNotePortRescanFlags* = set[ClapNotePortRescanFlag]

    ClapHostNotePorts* = ClapHostNotePortsT
    ClapHostNotePortsT* = object
        supported_dialects *: proc (host: ptr ClapHost): uint32 {.cdecl.}
        rescan             *: proc (host: ptr ClapHost, flags: uint32): void {.cdecl.}