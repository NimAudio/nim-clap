import ../clap
import std/[locks, math, strutils]

type
    ParameterKind* = enum
        pkFloat,
        pkInt,
        pkBool

    AutoModuSupport* = object
        base        *: bool
        per_note_id *: bool
        per_key     *: bool
        per_channel *: bool
        per_port    *: bool

    Parameter* = object
        name *: string
        path *: string
        case kind *: ParameterKind:
            of pkFloat:
                f_min       *: float64
                f_max       *: float64
                f_default   *: float64
                f_as_value  *: proc (str: string): float64
                f_as_string *: proc (val: float64): string
            of pkInt:
                i_min       *: int64
                i_max       *: int64
                i_default   *: int64
                i_as_value  *: proc (str: string): int64
                i_as_string *: proc (val: int64): string
            of pkBool:
                b_default *: bool
                true_str  *: string
                false_str *: string
        id          *: uint32
        is_periodic *: bool
        is_hidden   *: bool
        is_readonly *: bool
        is_bypass   *: bool
        is_enum     *: bool
        req_process *: bool
        automation  *: AutoModuSupport
        modulation  *: AutoModuSupport

    ParameterValue* = object
        param *: ref Parameter
        case kind *: ParameterKind:
            of pkFloat: f_value *: float64
            of pkInt:   i_value *: int64
            of pkBool:  b_value *: bool
        has_changed *: bool

    PluginDesc* = object
        id          *: string
        name        *: string
        vendor      *: string
        url         *: string
        manual_url  *: string
        support_url *: string
        version     *: string
        description *: string
        features    *: seq[string]

    Plugin* = object
        params         *: seq[Parameter]
        ui_param_data  *: seq[ParameterValue]
        dsp_param_data *: seq[ParameterValue]
        controls_mutex *: Lock
        latency        *: uint32
        sample_rate    *: float64
        desc           *: PluginDesc



proc convert_plugin_descriptor*(plugin: Plugin): ClapPluginDescriptor =
    result = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major:    CLAP_VERSION_MAJOR,
            minor:    CLAP_VERSION_MINOR,
            revision: CLAP_VERSION_REVISION),
        id: cstring(plugin.desc.id),
        name: cstring(plugin.desc.name),
        vendor: cstring(plugin.desc.vendor),
        url: cstring(plugin.desc.url),
        manual_url: cstring(plugin.desc.manual_url),
        support_url: cstring(plugin.desc.support_url),
        version: cstring(plugin.desc.version),
        description: cstring(plugin.desc.description),
        features: allocCStringArray(plugin.desc.features))

# let s_my_plug_desc* = 



proc nim_plug_audio_ports_count*(clap_plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 1

proc nim_plug_audio_ports_get*(clap_plugin: ptr ClapPlugin,
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

let s_nim_plug_audio_ports* = ClapPluginAudioPorts(count: nim_plug_audio_ports_count, get: nim_plug_audio_ports_get)

proc nim_plug_note_ports_count*(clap_plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.} =
    return 0

proc nim_plug_note_ports_get*(clap_plugin: ptr ClapPlugin,
                            index: uint32,
                            is_input: bool,
                            info: ptr ClapNotePortInfo): bool {.cdecl.} =
    return false

let s_nim_plug_note_ports* = ClapPluginNotePorts(count: nim_plug_note_ports_count, get: nim_plug_note_ports_get)

proc nim_plug_latency_get*(clap_plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    return cast[ptr Plugin](clap_plugin.plugin_data).latency

let s_nim_plug_latency* = ClapPluginLatency(get: nim_plug_latency_get)
proc nim_plug_params_count*(clap_plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    return uint32(len(plugin.params))

proc nim_plug_params_get_info*(clap_plugin: ptr ClapPlugin, index: uint32, information: ptr ClapParamInfo): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        var param = plugin.params[index]
        var flags: set[ClapParamInfoFlag]
        if param.kind == pkInt or param.kind == pkBool:
            flags.incl(cpiIS_STEPPED)
        if param.is_periodic : flags.incl(cpiIS_PERIODIC)
        if param.is_hidden   : flags.incl(cpiIS_HIDDEN)
        if param.is_readonly : flags.incl(cpiIS_READONLY)
        if param.is_bypass   : flags.incl(cpiIS_BYPASS)
        if param.req_process : flags.incl(cpiREQUIRES_PROCESS)
        if param.is_enum     : flags.incl(cpiIS_ENUM)
        if param.automation.base:
            flags.incl(cpiIS_AUTOMATABLE)
            if param.automation.per_note_id : flags.incl(cpiIS_AUTOMATABLE_PER_NOTE_ID)
            if param.automation.per_key     : flags.incl(cpiIS_AUTOMATABLE_PER_KEY)
            if param.automation.per_channel : flags.incl(cpiIS_AUTOMATABLE_PER_CHANNEL)
            if param.automation.per_port    : flags.incl(cpiIS_AUTOMATABLE_PER_PORT)
        if param.modulation.base:
            flags.incl(cpiIS_MODULATABLE)
            if param.modulation.per_note_id : flags.incl(cpiIS_MODULATABLE_PER_NOTE_ID)
            if param.modulation.per_key     : flags.incl(cpiIS_MODULATABLE_PER_KEY)
            if param.modulation.per_channel : flags.incl(cpiIS_MODULATABLE_PER_CHANNEL)
            if param.modulation.per_port    : flags.incl(cpiIS_MODULATABLE_PER_PORT)

        var min_val     = low(float64)
        var max_val     = high(float64)
        var default_val = 0.0
        case param.kind:
            of pkFloat:
                min_val     = param.f_min
                max_val     = param.f_max
                default_val = param.f_default
            of pkInt:
                min_val     = float64(param.i_min)
                max_val     = float64(param.i_max)
                default_val = float64(param.i_default)
            of pkBool:
                default_val = if param.b_default: 1.0 else: 0.0
        information[] = ClapParamInfo(
            id            : ClapID(index),
            flags         : flags,
            cookie        : nil, # figure this out and implement it
            name          : char_arr_name(param.name),
            module        : char_arr_path(param.path),
            min_value     : min_val,
            max_value     : max_val,
            default_value : default_val
        )
        return true
        # return information.min_value != 0 or information.max_value != 0

proc bool_to_float(b: bool): float64 =
    if b:
        return 1.0
    else:
        return 0.0

proc nim_plug_params_get_value*(clap_plugin: ptr ClapPlugin, id: ClapID, value: ptr float64): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var index = uint32(id)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        withLock(plugin.controls_mutex):
            var param = plugin.params[index]
            value[] = if plugin.ui_param_data[index].has_changed:
                        case plugin.ui_param_data[index].kind:
                            of pkFloat:
                                plugin.ui_param_data[index].f_value
                            of pkInt:
                                float64(plugin.ui_param_data[index].i_value)
                            of pkBool:
                                bool_to_float(plugin.ui_param_data[index].b_value)
                    else:
                        case plugin.dsp_param_data[index].kind:
                            of pkFloat:
                                plugin.dsp_param_data[index].f_value
                            of pkInt:
                                float64(plugin.dsp_param_data[index].i_value)
                            of pkBool:
                                bool_to_float(plugin.dsp_param_data[index].b_value)
        return true

template str_to_char_arr_ptr*(write: ptr UncheckedArray[char], read: string, write_size: uint32): void =
    let min_len = min(write_size, uint32(read.len))
    var i: uint32 = 0
    while i < min_len:
        write[i] = read[i]
        i += 1
    write[i] = '\0'

proc nim_plug_params_value_to_text*(clap_plugin: ptr ClapPlugin, id: ClapID, value: float64, display: ptr UncheckedArray[char], size: uint32): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var index = uint32(id)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        var param = plugin.params[index]
        case param.kind:
            of pkFloat:
                if param.f_as_string != nil:
                    str_to_char_arr_ptr(display, param.f_as_string(value), size)
                else:
                    str_to_char_arr_ptr(display, value.formatBiggestFloat(ffDecimal, 6), size)
            of pkInt:
                if param.i_as_string != nil:
                    str_to_char_arr_ptr(display, param.i_as_string(int64(value)), size)
                else:
                    str_to_char_arr_ptr(display, value.formatBiggestFloat(ffDecimal, 0), size)
            of pkBool:
                if value > 0.5:
                    str_to_char_arr_ptr(display, param.true_str, size)
                else:
                    str_to_char_arr_ptr(display, param.false_str, size)
        return true

proc simple_str_bool(s: string): bool =
    var c = s[0]
    case c:
        of 'y':
            return true
        of 't':
            return true
        of '1':
            return true
        of 'n':
            return false
        of 'f':
            return false
        of '0':
            return false
        else:
            return false

proc nim_plug_params_text_to_value*(clap_plugin: ptr ClapPlugin, id: ClapID, display: cstring, value: ptr float64): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    var index = uint32(id)
    if index >= uint32(len(plugin.params)):
        return false
    else:
        var param = plugin.params[index]
        case param.kind:
            of pkFloat:
                if param.f_as_value != nil:
                    value[] = param.f_as_value($display)
                else:
                    value[] = float64(parseFloat($display))
            of pkInt:
                if param.i_as_value != nil:
                    value[] = float64(param.i_as_value($display))
                else:
                    value[] = float64(parseFloat($display))
            of pkBool:
                value[] = bool_to_float(simple_str_bool($display))
        return true

# proc nim_plug_params_flush*(clap_plugin: ptr ClapPlugin, input: ptr ClapInputEvents, output: ptr ClapOutputEvents): void {.cdecl.} =
#     var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
#     let event_count = input.size(input)
#     sync_ui_to_dsp(plugin, output)
#     for i in 0 ..< event_count:
#         nim_plug_process_event(plugin, input.get(input, i))

# let s_nim_plug_params = ClapPluginParams(
#         count         : nim_plug_params_count,
#         get_info      : nim_plug_params_get_info,
#         get_value     : nim_plug_params_get_value,
#         value_to_text : nim_plug_params_value_to_text,
#         text_to_value : nim_plug_params_text_to_value,
#         flush         : nim_plug_params_flush
#     )