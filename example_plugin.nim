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
    info.flags = {capfIS_MAIN}
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

proc my_plug_process_event(myplug: ptr MyPlug, event: ptr ClapEventUnion): void =
    if event.kindNote.header.space_id == 0:
        case event.kindNote.header.event_type: # kindParamValMod for both, as the objects are identical
            of cetPARAM_VALUE: # actual knob changes or automation
                discard
            of cetPARAM_MOD: # per voice modulation
                discard
            else:
                discard

proc my_plug_process(plugin: ptr ClapPlugin, process: ptr ClapProcess): ClapProcessStatus =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    let num_frames: uint32 = process.frames_count
    let num_events: uint32 = process.in_events.size(process.in_events)
    var event_idx: uint32 = 0
    var next_event_frame: uint32 = if num_events > 0: 0 else: num_frames

    var i: uint32 = 0
    while i < num_frames:
        while event_idx < num_events and next_event_frame == i:
            let event: ptr ClapEventUnion = process.in_events.get(process.in_events, event_idx)
            if event.kindNote.header.time != i:
                next_event_frame = event.kindNote.header.time
                break

            my_plug_process_event(myplug, event)
            event_idx += 1

            if event_idx == num_events:
                next_event_frame = num_frames
                break

        while i < next_event_frame:
            let in_l: float32 = process.audio_inputs[0].data32[0][i]
            let in_r: float32 = process.audio_inputs[0].data32[1][i]

            let out_l = in_r * 0.5
            let out_r = in_l

            process.audio_outputs[0].data32[0][i] = out_l
            process.audio_outputs[0].data32[1][i] = out_r

            i += 1
    return cpsCONTINUE

proc my_plug_get_extension(plugin: ptr ClapPlugin, id: cstring): pointer =
    case id:
        of CLAP_EXT_LATENCY:
            return addr s_my_plug_latency
        of CLAP_EXT_AUDIO_PORTS:
            return addr s_my_plug_audio_ports
        of CLAP_EXT_NOTE_PORTS:
            return addr s_my_plug_note_ports
        of CLAP_EXT_STATE:
            return addr s_my_plug_state
