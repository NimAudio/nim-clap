import clap


echo(CLAP_VERSION_MAJOR)

let features: cstringArray = allocCStringArray([CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
                                                CLAP_PLUGIN_FEATURE_EQUALIZER,
                                                CLAP_PLUGIN_FEATURE_DISTORTION,
                                                CLAP_PLUGIN_FEATURE_STEREO])

let bgeq_plug_desc = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major: CLAP_VERSION_MAJOR,
            minor: CLAP_VERSION_MINOR,
            revision: CLAP_VERSION_REVISION),
        id: "com.unconventionalwaves.bonsai.geq",
        name: "Bonsai Graphic EQ",
        vendor: "Unconventional Waves",
        url: "https://www.unconventionalwave.com/bonsai/geq",
        manual_url: "https://www.unconventionalwave.com/bonsai/geq",
        support_url: "https://www.unconventionalwave.com/bonsai/geq",
        version: "0.6",
        description: "highly nonlinear, 5 channel, 17 band graphic equalizer",
        features: features)

echo(bgeq_plug_desc.clap_version.minor)
echo(bgeq_plug_desc.features[1])
echo(CLAP_EXT_AUDIO_PORTS)

proc my_plug_audio_ports_count(plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 1

proc my_plug_audio_ports_get(plugin: ptr ClapPlugin,
                            index: uint32,
                            is_input: bool,
                            info: ptr ClapAudioPortInfo): bool {.cdecl.} =
    if index > 0:
        return false
    info.id = 0.ClapID
    echo(info.name)
    info.channel_count = 2
    info.flags = {CLAP_AUDIO_PORT_IS_MAIN}
    info.port_type = CLAP_PORT_STEREO
    info.in_place_pair = CLAP_INVALID_ID
    return true

let s_my_plug_audio_ports = ClapPluginAudioPorts(count: my_plug_audio_ports_count, get: my_plug_audio_ports_get)

proc my_plug_note_ports_count(plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 0

proc my_plug_note_ports_get(plugin: ptr ClapPlugin,
                            index: uint32,
                            is_input: bool,
                            info: ptr ClapNotePortInfo): bool {.cdecl.} =
    return false

let s_my_plug_note_ports = ClapPluginNotePorts(count: my_plug_note_ports_count, get: my_plug_note_ports_get)

proc my_plug_latency_get(plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    return cast[ptr MyPlug](plugin.plugin_data).latency # TODO convince araq to add forward type declaration to nim

let s_my_plug_latency = ClapPluginLatency(get: my_plug_latency_get)

proc my_plug_state_save(plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    # TODO write state into stream
    return true

proc my_plug_state_load(plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    # TODO write state into stream
    return true

let s_my_plug_state = ClapPluginState(save: my_plug_state_save, load: my_plug_state_load)

proc my_plug_init(plugin: ptr ClapPlugin): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    myplug.host_log          = cast[ptr ClapHostLog         ](myplug.host.get_extension(myplug.host, CLAP_EXT_LOG          ))
    myplug.host_thread_check = cast[ptr ClapHostThreadCheck ](myplug.host.get_extension(myplug.host, CLAP_EXT_THREAD_CHECK ))
    myplug.host_latency      = cast[ptr ClapHostLatency     ](myplug.host.get_extension(myplug.host, CLAP_EXT_LATENCY      ))
    myplug.host_state        = cast[ptr ClapHostState       ](myplug.host.get_extension(myplug.host, CLAP_EXT_STATE        ))
    return true

proc my_plug_destroy(plugin: ptr ClapPlugin): void {.cdecl.} =
    dealloc(cast[ptr MyPlug](plugin.plugin_data))

proc my_plug_activate(plugin: ptr ClapPlugin,
                        sample_rate: float64,
                        min_frames_count: uint32,
                        max_frames_count: uint32): bool {.cdecl.} =
    return true

proc my_plug_deactivate(plugin: ptr ClapPlugin): void =
    discard

proc my_plug_start_processing(plugin: ptr ClapPlugin): bool =
    return true

proc my_plug_stop_processing(plugin: ptr ClapPlugin): void =
    discard

proc my_plug_reset(plugin: ptr ClapPlugin): void =
    discard

proc my_plug_process_event(myplug: MyPlug)