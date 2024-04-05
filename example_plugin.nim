import clap
import std/[locks, math, strutils]

type
    # EventMessage* = object
    #     id          *: uint16
    #     index       *: uint16
    #     last_value  *: float32
    #     next_value  *: float32
    #     blend_steps *: uint32

    # EventIDInfo* = object
    #     value  *: ptr UncheckedArray[float32]
    #     length *: uint16

    # EventBuffer* = object
    #     index   *: Atomic[int16]
    #     buffer  *: ptr array[2048, EventMessage]
    #     id_info *: ptr UncheckedArray[EventIDInfo]

    Changed*[T] = object
        changed *: bool
        value   *: T

    ControlValues* = object
        level  *: Changed[float32]
        flip   *: Changed[float32]
        rotate *: Changed[float32]

    AudioThreadData* = object
        smoothed_level  *: float32
        smoothed_flip   *: float32
        smoothed_rotate *: float32

    MyPlug* = object
        plugin            *: ClapPlugin
        host              *: ptr ClapHost
        host_latency      *: ptr ClapHostLatency
        host_log          *: ptr ClapHostLog
        host_thread_check *: ptr ClapHostThreadCheck
        host_state        *: ptr ClapHostState
        host_params       *: ptr ClapHostParams
        latency           *: uint32
        ui_controls       *: ControlValues
        dsp_controls      *: ControlValues
        controls_mutex    *: Lock
        audio_data        *: AudioThreadData
        smooth_coef       *: float32
        sample_rate       *: float64

converter changeable*[T](value: T): Changed[T] =
    result = Changed[T](changed: true, value: value)

converter changed_value*[T](changed: Changed[T]): T =
    result = changed.value

converter changed_changed*[T](changed: Changed[T]): bool =
    result = changed.changed

proc `<-`*[T](c_to, c_from: var Changed[T]): void =
    if c_from.changed:
        c_from.changed = false
        c_to = c_from

const pi: float32 = 3.1415926535897932384626433832795

# based on reaktor one pole lowpass coef calculation
proc onepole_lp_coef(freq: float32, sr: float32): float32 =
    var input: float32 = min(0.5 * pi, max(0.001, freq) * (pi / sr));
    var tanapprox: float32 = (((0.0388452 - 0.0896638 * input) * input + 1.00005) * input) /
                            ((0.0404318 - 0.430871 * input) * input + 1);
    return tanapprox / (tanapprox + 1);

# based on reaktor one pole lowpass
proc onepole_lp(last: var float32, coef: float32, src: float32): float32 =
    var delta_scaled: float32 = (src - last) * coef;
    var dst: float32 = delta_scaled + last;
    last = delta_scaled + dst;
    return dst;

proc simple_lp_coef(freq: float32, sr: float32): float32 =
    var w: float32 = (2 * pi * freq) / sr;
    var twomcos: float32 = 2 - cos(w);
    return 1 - (twomcos - sqrt(twomcos * twomcos - 1));

proc simple_lp(smooth: var float32, coef: float32, next: float32): var float32 =
    smooth += coef * (next - smooth)
    return smooth

echo(CLAP_VERSION_MAJOR)

let features*: cstringArray = allocCStringArray([CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
                                                CLAP_PLUGIN_FEATURE_EQUALIZER,
                                                CLAP_PLUGIN_FEATURE_DISTORTION,
                                                CLAP_PLUGIN_FEATURE_STEREO])

let s_my_plug_desc* = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major: CLAP_VERSION_MAJOR,
            minor: CLAP_VERSION_MINOR,
            revision: CLAP_VERSION_REVISION),
        id: "com.nimclap.example",
        name: "nim-clap example plugin",
        vendor: "nim-clap",
        url: "https://www.github.com/morganholly/nim-clap",
        manual_url: "https://www.github.com/morganholly/nim-clap",
        support_url: "https://www.github.com/morganholly/nim-clap",
        version: "0.6",
        description: "example effect plugin",
        features: features)

echo(s_my_plug_desc.clap_version.minor)
echo(s_my_plug_desc.features[1])
echo(CLAP_EXT_AUDIO_PORTS)

#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: ports
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

proc my_plug_audio_ports_count*(plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 1

proc my_plug_audio_ports_get*(plugin: ptr ClapPlugin,
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

let s_my_plug_audio_ports* = ClapPluginAudioPorts(count: my_plug_audio_ports_count, get: my_plug_audio_ports_get)

proc my_plug_note_ports_count*(plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 0

proc my_plug_note_ports_get*(plugin: ptr ClapPlugin,
                            index: uint32,
                            is_input: bool,
                            info: ptr ClapNotePortInfo): bool {.cdecl.} =
    return false

let s_my_plug_note_ports* = ClapPluginNotePorts(count: my_plug_note_ports_count, get: my_plug_note_ports_get)

proc my_plug_latency_get*(plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    return cast[ptr MyPlug](plugin.plugin_data).latency # TODO convince araq to add forward type declaration to nim

let s_my_plug_latency* = ClapPluginLatency(get: my_plug_latency_get)

#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: state and sync
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

proc cond_set_with_event*[T](c_to, c_from: var Changed[T], id: ClapID, output: ptr ClapOutputEvents): void =
    if c_from.changed:
        c_from.changed = false
        c_to = c_from

        var event: ClapEventUnion
        event.kindParamValMod = ClapEventParamValue(
            header     : ClapEventHeader(
                size       : uint32(ClapEventParamValue.sizeof),
                time       : 0,
                space_id   : 0,
                event_type : cetPARAM_VALUE,
                flags      : {}
            ),
            param_id   : id,
            cookie     : nil,
            note_id    : -1,
            port_index : -1,
            channel    : -1,
            key        : -1,
            val_amt    : float64(c_to.value)
        )

        discard output.try_push(output, addr event)

proc sync_ui_to_dsp*(myplug: ptr MyPlug, output: ptr ClapOutputEvents): void =
    withLock(myplug.controls_mutex):
        # conditional set proc for Changed[T], but doesn't make events
        # myplug.dsp_controls.level  <- myplug.ui_controls.level
        # myplug.dsp_controls.flip   <- myplug.ui_controls.flip
        # myplug.dsp_controls.rotate <- myplug.ui_controls.rotate
        cond_set_with_event(myplug.dsp_controls.level,  myplug.ui_controls.level,  ClapID(0), output)
        cond_set_with_event(myplug.dsp_controls.flip,   myplug.ui_controls.flip,   ClapID(1), output)
        cond_set_with_event(myplug.dsp_controls.rotate, myplug.ui_controls.rotate, ClapID(2), output)

proc sync_dsp_to_ui*(myplug: ptr MyPlug): void =
    withLock(myplug.controls_mutex):
        myplug.ui_controls.level  <- myplug.dsp_controls.level
        myplug.ui_controls.flip   <- myplug.dsp_controls.flip
        myplug.ui_controls.rotate <- myplug.dsp_controls.rotate

proc my_plug_state_save*(plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    sync_dsp_to_ui(myplug)
    var data: array[3, float32] = [myplug.ui_controls.level.value,
                                myplug.ui_controls.flip.value,
                                myplug.ui_controls.rotate.value]
    return float32.sizeof * 3 == stream.write(stream, addr data, float32.sizeof * 3)

proc my_plug_state_load*(plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    var data: array[3, float32]
    withLock(myplug.controls_mutex):
        if float32.sizeof * 3 == stream.read(stream, addr data, float32.sizeof * 3):
            myplug.ui_controls.level  = data[0] # converter on float32 to Changed[float32]
            myplug.ui_controls.flip   = data[1] # sets changed bool to true
            myplug.ui_controls.rotate = data[2]
            return true
        else:
            return false

let s_my_plug_state* = ClapPluginState(save: my_plug_state_save, load: my_plug_state_load)

#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: process
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

proc my_plug_start_processing*(plugin: ptr ClapPlugin): bool {.cdecl.} =
    return true

proc my_plug_stop_processing*(plugin: ptr ClapPlugin): void {.cdecl.} =
    discard

proc my_plug_reset*(plugin: ptr ClapPlugin): void {.cdecl.} =
    discard

proc my_plug_process_event*(myplug: ptr MyPlug, event: ptr ClapEventUnion): void {.cdecl.} =
    myplug.dsp_controls.level = float32(event.kindParamValMod.val_amt)
    # if event.kindNote.header.space_id == 0:
    #     case event.kindNote.header.event_type: # kindParamValMod for both, as the objects are identical
    #         of cetPARAM_VALUE: # actual knob changes or automation
    #             withLock(myplug.controls_mutex):
    #                 case event.kindParamValMod.param_id:
    #                     of ClapID(0):
    #                         myplug.dsp_controls.level = float32(event.kindParamValMod.val_amt)
    #                     of ClapID(1):
    #                         myplug.dsp_controls.flip = float32(event.kindParamValMod.val_amt)
    #                     of ClapID(2):
    #                         myplug.dsp_controls.rotate = float32(event.kindParamValMod.val_amt)
    #                     else:
    #                         discard
    #         of cetPARAM_MOD: # per voice modulation
    #             discard
    #         else:
    #             discard

proc db_af*(db: float32): float32 =
    result = pow(10, 0.05 * db)
proc db_af*(db: float64): float64 =
    result = pow(10, 0.05 * db)

proc af_db*(af: float32): float32 =
    result = 20 * log10(af)
proc af_db*(af: float64): float64 =
    result = 20 * log10(af)

proc lerp*(x, y, mix: float32): float32 =
    result = (y - x) * mix + x

proc my_plug_process*(plugin: ptr ClapPlugin, process: ptr ClapProcess): ClapProcessStatus {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)

    myplug.sync_ui_to_dsp(process.out_events)

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

            # if event != nil: # crashes, idk what to do for logs
            #     var file = open("/Users/alix/Documents/GitHub/nim-clap/log.txt", fmAppend)
            #     try:
            #         file.write(event.kindParamValMod.header.space_id)
            #         file.write(" ")
            #         file.write(event.kindParamValMod.header.event_type)
            #         file.write(" ")
            #         file.write(event.kindParamValMod.param_id)
            #         file.write(" ")
            #         file.write(event.kindParamValMod.val_amt)
            #         file.write("\n")
            #     finally:
            #         close(file)

            my_plug_process_event(myplug, event)
            event_idx += 1

            if event_idx == num_events:
                next_event_frame = num_frames
                break

        while i < next_event_frame:
            discard myplug.audio_data.smoothed_level
                        .simple_lp(myplug.smooth_coef, myplug.dsp_controls.level)
            discard myplug.audio_data.smoothed_flip
                        .simple_lp(myplug.smooth_coef, myplug.dsp_controls.flip)
            discard myplug.audio_data.smoothed_rotate
                        .simple_lp(myplug.smooth_coef, myplug.dsp_controls.rotate)

            let in_l: float32 = process.audio_inputs[0].data32[0][i]
            let in_r: float32 = process.audio_inputs[0].data32[1][i]

            # let out_l = in_r * 0.5
            # let out_r = in_l
            var out_l = myplug.audio_data.smoothed_level * in_l
            var out_r = myplug.audio_data.smoothed_level * in_r
            out_l = lerp(out_l, out_r, myplug.audio_data.smoothed_flip)
            out_r = lerp(out_r, out_l, myplug.audio_data.smoothed_flip)
            let a_cos: float32 = cos(myplug.audio_data.smoothed_rotate)
            let a_sin: float32 = sin(myplug.audio_data.smoothed_rotate)
            out_l = out_l * a_cos + out_r * a_sin
            out_l = out_r * a_cos - out_l * a_sin

            process.audio_outputs[0].data32[0][i] = out_l
            process.audio_outputs[0].data32[1][i] = out_r

            i += 1
    return cpsCONTINUE

#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: params
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

proc my_plug_params_count*(plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    return 3

proc my_plug_params_get_info*(plugin: ptr ClapPlugin, index: uint32, information: ptr ClapParamInfo): bool {.cdecl.} =
    case index:
        of 0: # level
            information[] = ClapParamInfo(
                id            : ClapID(0),
                flags         : {cpiIS_AUTOMATABLE, cpiIS_MODULATABLE, cpiREQUIRES_PROCESS},
                cookie        : nil,
                name          : char_arr_name("Level"),
                module        : char_arr_name(""),
                min_value     : -48.0,
                max_value     : 24.0,
                default_value : 0.0
            )
        of 1: # flip
            information[] = ClapParamInfo(
                id            : ClapID(1),
                flags         : {cpiIS_AUTOMATABLE, cpiIS_MODULATABLE, cpiREQUIRES_PROCESS},
                cookie        : nil,
                name          : char_arr_name("Flip"),
                module        : char_arr_name(""),
                min_value     : 0.0,
                max_value     : 1.0,
                default_value : 0.0
            )
        of 2: # rotate
            information[] = ClapParamInfo(
                id            : ClapID(2),
                flags         : {cpiIS_AUTOMATABLE, cpiIS_MODULATABLE, cpiREQUIRES_PROCESS},
                cookie        : nil,
                name          : char_arr_name("Rotate"),
                module        : char_arr_name(""),
                min_value     : -pi,
                max_value     : pi,
                default_value : 0.0
            )
        else:
            return false
    return information.min_value != 0 or information.max_value != 0

proc my_plug_params_get_value*(plugin: ptr ClapPlugin, id: ClapID, value: ptr float64): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    withLock(myplug.controls_mutex):
        case id:
            of ClapID(0):
                value[] = if myplug.ui_controls.level.changed:
                            myplug.ui_controls.level.value
                        else:
                            myplug.dsp_controls.level.value
            of ClapID(1):
                value[] = if myplug.ui_controls.flip.changed:
                            myplug.ui_controls.flip.value
                        else:
                            myplug.dsp_controls.flip.value
            of ClapID(2):
                value[] = if myplug.ui_controls.rotate.changed:
                            myplug.ui_controls.rotate.value
                        else:
                            myplug.dsp_controls.rotate.value
            else:
                return false
    return true

template str_to_char_arr_ptr*(write: ptr UncheckedArray[char], read: string, write_size: uint32): void =
    let min_len = min(write_size, uint32(read.len))
    var i: uint32 = 0
    while i < min_len:
        write[i] = read[i]
        i += 1
    write[i] = '\0'

proc my_plug_params_value_to_text*(plugin: ptr ClapPlugin, id: ClapID, value: float64, display: ptr UncheckedArray[char], size: uint32): bool {.cdecl.} =
    case id:
        of ClapID(0):
            # str_to_char_arr_ptr(display, $af_db(value) & " db", size)
            str_to_char_arr_ptr(display, $value & " db", size)
        of ClapID(1):
            str_to_char_arr_ptr(display, $value, size)
        of ClapID(2):
            str_to_char_arr_ptr(display, $value, size)
        else:
            return false
    return true

proc my_plug_params_text_to_value*(plugin: ptr ClapPlugin, id: ClapID, display: cstring, value: ptr float64): bool {.cdecl.} =
    case id:
        of ClapID(0):
            value[] = float64(parseFloat(($display).strip().split(" ")[0]))
        of ClapID(1):
            value[] = float64(parseFloat($display))
        of ClapID(2):
            value[] = float64(parseFloat($display))
        else:
            return false
    return true

proc my_plug_params_flush*(plugin: ptr ClapPlugin, input: ptr ClapInputEvents, output: ptr ClapOutputEvents): void {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    let event_count = input.size(input)
    sync_ui_to_dsp(myplug, output)
    for i in 0 ..< event_count:
        my_plug_process_event(myplug, input.get(input, i))

let s_my_plug_params = ClapPluginParams(
        count         : my_plug_params_count,
        get_info      : my_plug_params_get_info,
        get_value     : my_plug_params_get_value,
        value_to_text : my_plug_params_value_to_text,
        text_to_value : my_plug_params_text_to_value,
        flush         : my_plug_params_flush
    )

#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: creation, entry, activation, deactivation
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

proc my_plug_init*(plugin: ptr ClapPlugin): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    myplug.host_log          = cast[ptr ClapHostLog         ](myplug.host.get_extension(myplug.host, CLAP_EXT_LOG          ))
    myplug.host_thread_check = cast[ptr ClapHostThreadCheck ](myplug.host.get_extension(myplug.host, CLAP_EXT_THREAD_CHECK ))
    myplug.host_latency      = cast[ptr ClapHostLatency     ](myplug.host.get_extension(myplug.host, CLAP_EXT_LATENCY      ))
    myplug.host_state        = cast[ptr ClapHostState       ](myplug.host.get_extension(myplug.host, CLAP_EXT_STATE        ))
    myplug.host_params       = cast[ptr ClapHostParams      ](myplug.host.get_extension(myplug.host, CLAP_EXT_PARAMS       ))
    var level : float32 = 1
    var flip  : float32 = 0
    var rotate: float32 = 0
    myplug.audio_data.smoothed_level  = level
    myplug.audio_data.smoothed_flip   = flip
    myplug.audio_data.smoothed_rotate = rotate
    myplug.dsp_controls.level         = level
    myplug.dsp_controls.flip          = flip
    myplug.dsp_controls.rotate        = rotate
    myplug.ui_controls.level          = level
    myplug.ui_controls.flip           = flip
    myplug.ui_controls.rotate         = rotate
    initLock(myplug.controls_mutex)
    return true

proc my_plug_destroy*(plugin: ptr ClapPlugin): void {.cdecl.} =
    dealloc(cast[ptr MyPlug](plugin.plugin_data))

proc my_plug_activate*(plugin: ptr ClapPlugin,
                        sample_rate: float64,
                        min_frames_count: uint32,
                        max_frames_count: uint32): bool {.cdecl.} =
    var myplug = cast[ptr MyPlug](plugin.plugin_data)
    myplug.sample_rate = sample_rate
    myplug.smooth_coef = simple_lp_coef(10, sample_rate)
    return true

proc my_plug_deactivate*(plugin: ptr ClapPlugin): void {.cdecl.} =
    discard

proc my_plug_get_extension*(plugin: ptr ClapPlugin, id: cstring): pointer {.cdecl.} =
    case id:
        of CLAP_EXT_LATENCY:
            return addr s_my_plug_latency
        of CLAP_EXT_AUDIO_PORTS:
            return addr s_my_plug_audio_ports
        of CLAP_EXT_NOTE_PORTS:
            return addr s_my_plug_note_ports
        of CLAP_EXT_STATE:
            return addr s_my_plug_state
        of CLAP_EXT_PARAMS:
            return addr s_my_plug_params

proc my_plug_on_main_thread*(plugin: ptr ClapPlugin): void {.cdecl.} =
    discard

proc my_plug_create*(host: ptr ClapHost): ptr ClapPlugin {.cdecl.} =
    var myplug = cast[ptr MyPlug](alloc0(MyPlug.sizeof))
    myplug.host = host
    # myplug.plugin = cast[ptr ClapPlugin](alloc0(ClapPlugin.sizeof))
    myplug.plugin.desc = addr s_my_plug_desc
    myplug.plugin.plugin_data = myplug
    myplug.plugin.init = my_plug_init
    myplug.plugin.destroy = my_plug_destroy
    myplug.plugin.activate = my_plug_activate
    myplug.plugin.deactivate = my_plug_deactivate
    myplug.plugin.start_processing = my_plug_start_processing
    myplug.plugin.stop_processing = my_plug_stop_processing
    myplug.plugin.reset = my_plug_reset
    myplug.plugin.process = my_plug_process
    myplug.plugin.get_extension = my_plug_get_extension
    myplug.plugin.on_main_thread = my_plug_on_main_thread
    return addr myplug.plugin

type
    ClapDescCreate* = object
        desc *: ptr ClapPluginDescriptor
        create *: proc (host: ptr ClapHost): ptr ClapPlugin {.cdecl.}

const plugin_count*: uint32 = 1

let s_plugins: array[plugin_count, ClapDescCreate] = [
    ClapDescCreate(desc: addr s_my_plug_desc, create: my_plug_create)
]

proc plugin_factory_get_plugin_count*(factory: ptr ClapPluginFactory): uint32 {.cdecl.} =
    return plugin_count

proc plugin_factory_get_plugin_descriptor*(factory: ptr ClapPluginFactory, index: uint32): ptr ClapPluginDescriptor {.cdecl.} =
    return s_plugins[index].desc

proc plugin_factory_create_plugin*(factory: ptr ClapPluginFactory,
                                    host: ptr ClapHost,
                                    plugin_id: cstring): ptr ClapPlugin {.cdecl.} =
    if host.clap_version.major < 1:
        return nil

    for i in 0 ..< plugin_count:
        if plugin_id == s_plugins[i].desc.id:
            return s_plugins[i].create(host)

    return nil

let s_plugin_factory* = ClapPluginFactory(
    get_plugin_count: plugin_factory_get_plugin_count,
    get_plugin_descriptor: plugin_factory_get_plugin_descriptor,
    create_plugin: plugin_factory_create_plugin)

proc entry_init*(plugin_path: cstring): bool {.cdecl.} =
    return true

proc entry_deinit*(): void {.cdecl.} =
    discard

var g_entry_init_counter = 0

proc entry_init_guard*(plugin_path: cstring): bool {.cdecl.} =
    # add mutex lock
    g_entry_init_counter += 1
    var succeed = true
    if g_entry_init_counter == 1:
        succeed = entry_init(plugin_path)
        if not succeed:
            g_entry_init_counter = 0
    # mutex unlock
    return succeed

proc entry_deinit_guard*(): void {.cdecl.} =
    # add mutex lock
    g_entry_init_counter -= 1
    if g_entry_init_counter == 0:
        entry_deinit()
    # mutex unlock

proc entry_get_factory*(factory_id: cstring): ptr ClapPluginFactory {.cdecl.} =
    if g_entry_init_counter <= 0:
        return nil
    if factory_id == CLAP_PLUGIN_FACTORY_ID:
        return addr s_plugin_factory
    return nil

let clap_entry* {.global, exportc: "clap_entry", dynlib.} = ClapPluginEntry(
    clap_version: CLAP_VERSION_INIT,
    init: entry_init_guard,
    deinit: entry_deinit_guard,
    get_factory: entry_get_factory
)
