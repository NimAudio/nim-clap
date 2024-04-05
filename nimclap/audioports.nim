import shared, process

const
    CLAP_EXT_AUDIO_PORTS *: cstring = "clap.audio-ports"
    CLAP_PORT_MONO       *: cstring = "mono"
    CLAP_PORT_STEREO     *: cstring = "stereo"


type
    ClapAudioPortFlag* {.size:sizeof(uint32).} = enum
        capfIS_MAIN,
        capfSUPPORTS_64BITS,
        capfPREFERS_64BITS,
        capfREQUIRES_COMMON_SAMPLE_SIZE
    ClapAudioPortFlags* = distinct uint32

converter conv_clap_audio_port_flags*(flags: set[ClapAudioPortFlag]): ClapAudioPortFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (1'u32 shl ord(f))
    return ClapAudioPortFlags(res)

type
    ClapAudioPortRescanFlag* {.size:sizeof(uint32).} = enum
        caprNAMES,
        caprFLAGS,
        caprCHANNEL_COUNT,
        caprPORT_TYPE,
        caprIN_PLACE_PAIR,
        caprLIST
    ClapAudioPortRescanFlags* = distinct uint32

converter conv_clap_audio_port_rescan_flags*(flags: set[ClapAudioPortRescanFlag]): ClapAudioPortRescanFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (1'u32 shl ord(f))
    return ClapAudioPortRescanFlags(res)

type
    ClapAudioPortInfo* = ClapAudioPortInfoT
    ClapAudioPortInfoT* = object
        id            *: ClapID
        name          *: array[CLAP_NAME_SIZE, char]
        flags         *: ClapAudioPortFlags
        channel_count *: uint32
        port_type     *: cstring # CLAP_PORT_MONO | CLAP_PORT_STEREO
        in_place_pair *: ClapID # if in place supported, set to pair port id, else set to CLAP_INVALID_ID

    ClapPluginAudioPorts* = ClapPluginAudioPortsT
    ClapPluginAudioPortsT* = object
        count *: proc (plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.}
        get   *: proc (plugin: ptr ClapPlugin,
                        index: uint32,
                        is_input: bool,
                        info: ptr ClapAudioPortInfo): bool {.cdecl.}

    ClapHostAudioPorts* = ClapHostAudioPortsT
    ClapHostAudioPortsT* = object
        is_rescan_flag_supported *: proc (host: ptr ClapHost, flags: ClapAudioPortRescanFlags): bool {.cdecl.}
        rescan                   *: proc (host: ptr ClapHost, flags: ClapAudioPortRescanFlags): void {.cdecl.}