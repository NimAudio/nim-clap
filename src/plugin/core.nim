import ../clap
import std/[locks, math, strutils, bitops, tables]
# import jsony


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
        id_map         *: Table[int, int]
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



proc cond_set*(c_to, c_from: var ParameterValue): void =
    if c_from.has_changed:
        c_from.has_changed = false
        c_to.has_changed = false
        case c_from.kind:
            of pkFloat:
                c_to.f_value = c_from.f_value
            of pkInt:
                c_to.i_value = c_from.i_value
            of pkBool:
                c_to.b_value = c_from.b_value

proc cond_set_with_event*(c_to, c_from: var ParameterValue, id: ClapID, output: ptr ClapOutputEvents): void =
    if c_from.has_changed:
        c_from.has_changed = false
        c_to.has_changed = false
        var value: float64 = 0.0
        case c_from.kind:
            of pkFloat:
                c_to.f_value = c_from.f_value
                value = c_from.f_value
            of pkInt:
                c_to.i_value = c_from.i_value
                value = float64(c_from.i_value)
            of pkBool:
                c_to.b_value = c_from.b_value
                value = if c_from.b_value:
                            1.0
                        else:
                            0.0
        # c_to = c_from

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
            val_amt    : value
        )

        discard output.try_push(output, addr event)

proc sync_ui_to_dsp*(plugin: ptr Plugin, output: ptr ClapOutputEvents): void =
    withLock(plugin.controls_mutex):
        for i in 0 ..< len(plugin.ui_param_data):
            cond_set_with_event(plugin.dsp_param_data[i],  plugin.ui_param_data[i],  ClapID(i), output)

proc sync_dsp_to_ui*(plugin: ptr Plugin): void =
    withLock(plugin.controls_mutex):
        for i in 0 ..< len(plugin.ui_param_data):
            cond_set(plugin.dsp_param_data[i],  plugin.ui_param_data[i])

# type
#     JSONParamValue* = object
#         id *: uint32
#         case kind *: ParameterKind:
#             of pkFloat: f_value *: float64
#             of pkInt:   i_value *: int64
#             of pkBool:  b_value *: bool

# converter param_val_to_json*(pval: ParameterValue): JSONParamValue =
#     case pval.kind:
#         of pkFloat:
#             result = JSONParamValue(
#                 id: pval.param.id,
#                 kind: pkFloat,
#                 f_value: pval.f_value
#             )
#         of pkInt:
#             result = JSONParamValue(
#                 id: pval.param.id,
#                 kind: pkInt,
#                 i_value: pval.i_value
#             )
#         of pkBool:
#             result = JSONParamValue(
#                 id: pval.param.id,
#                 kind: pkBool,
#                 b_value: pval.b_value
#             )

# type
#     JSONSave* = object
#         plugin_id       *: string
#         plugin_version  *: string
#         param_data *: seq[JSONParamValue]

proc get_byte_at*[T: SomeInteger](val: T, position: int): byte =
    # result = cast[byte]((val shr (position shl 3)) and 0b1111_1111)
    result = cast[byte](val.bitsliced(position ..< position + 8))

template `+`[T](p: ptr T, off: int): ptr T =
    cast[ptr type(p[])](cast[ByteAddress](p) +% off * sizeof(p[]))

proc `[]=`[T](p: ptr[T], i: int, x: T) =
    (p + i)[] = x

proc `[]=`(p: ptr[byte], i: int, x: byte) =
    (p + i)[] = x

# proc `[]=`[T](p: ptr[byte]; i: var uint; x: T) =
#     for j in 0 ..< (T.sizeof):
#         i += 1
#         p[i] = get_byte_at[T](x, uint8(i))

proc `[]=`[T](p: ptr[byte], i: int, x: T) =
    for j in 0 ..< (T.sizeof):
        p[int(j) + i] = get_byte_at[T](x, int(i))

proc `[]`[T](p: ptr[T], i: int): T =
    result = (p + i)[]

proc read_as[T](p: ptr[byte], i: int): T =
    var temp: uint64
    for j in 0 ..< (T.sizeof):
        temp.setMask((p + i + j)[] shl (j * 8))
    result = cast[T](temp)

proc `->`[T](i: var int, x: T) =
    i += int(x.sizeof)
proc `<-`[T](i: var int, x: T) =
    i -= int(x.sizeof)

proc my_plug_state_save*(clap_plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    sync_dsp_to_ui(plugin)
    #TODO update and replace this
    #TODO - maybe add error correction
    #TODO - maybe store the plugin id and version and add a stored callback for version checks
    #TODO - maybe use json, protobuf, whatever, which would allow for nested state
    #TODO - nested state would be necessary for non-parameter stateful data
    # var json_param_vals: seq[JSONParamValue]
    # for i in plugin.ui_param_data:
    #     json_param_vals.add(i)
    # var save = JSONSave(
    #     plugin_id: plugin.desc.id,
    #     plugin_version: plugin.desc.version,
    #     param_data: json_param_vals)
    # let json_str = save.toJson()
    # let json_size_32: uint32 = uint32(json_str.sizeof)
    # let json_str_size: string =
    #     json_size_32 and 1111_1111_0000_0000_0000_0000_0000_0000
    # toBin(json_size_32, 4)
    var visible_editable_param_count = 0
    for p in plugin.params:
        if (not p.is_hidden) and (not p.is_readonly):
            visible_editable_param_count += 1
    var buf_size = uint32(visible_editable_param_count * (
                                Parameter.id.sizeof +
                                ParameterValue.has_changed.sizeof +
                                ParameterValue.f_value.sizeof
                            ) + 4) #uint32 4, bool 1, float64 8
    var buffer: ptr[byte] = cast[ptr[byte]](alloc0(buf_size))
    var index = 0
    buffer[index] = buf_size
    index -> buf_size
    for p_i in 0 ..< len(plugin.params):
        var p = plugin.params[p_i]
        var v = plugin.ui_param_data[p_i]
        if (not p.is_hidden) and (not p.is_readonly):
            buffer[index] = p.id
            index -> p.id
            buffer[index] = cast[uint8](v.has_changed)
            index -> v.has_changed
            case v.kind:
                of pkFloat:
                    buffer[index] = cast[uint64](v.f_value)
                    index -> v.f_value
                of pkInt:
                    buffer[index] = v.i_value
                    index -> v.i_value
                of pkBool:
                    buffer[index] = cast[uint8](v.b_value)
                    index += int(ParameterValue.f_value.sizeof)
    var written_size = 0
    while written_size < int(buf_size):
        let status = stream.write(stream, buffer + written_size, uint64(int(buf_size) - written_size))
        if status > 0:
            written_size += status
        else:
            return false
    return true

proc my_plug_state_load*(clap_plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    withLock(plugin.controls_mutex):
        var buf_size: uint32 = 0
        if stream.read(stream, addr buf_size, uint64(uint32.sizeof)) > 0:
            var buffer: ptr[byte] = cast[ptr[byte]](alloc0(int(buf_size) - uint32.sizeof))
            var read_size = 0
            while read_size < int(buf_size):
                let status = stream.read(stream, buffer + read_size, uint64(int(buf_size) - read_size))
                if status > 0:
                    read_size += status
                else:
                    return false
            var index = 0
            for b_i in countup(0, int(buf_size), (
                                Parameter.id.sizeof +
                                ParameterValue.has_changed.sizeof +
                                ParameterValue.f_value.sizeof
                            )):
                var i_offset = 0
                var p_i = plugin.id_map[int(read_as[uint32](buffer, b_i))]
                var v = plugin.ui_param_data[p_i]
                i_offset += uint32.sizeof
                v.has_changed = read_as[bool](buffer, b_i + i_offset)
                i_offset += bool.sizeof
                case v.kind:
                    of pkFloat:
                        v.f_value = read_as[float64](buffer, b_i + i_offset)
                    of pkInt:
                        v.i_value = read_as[int64](buffer, b_i + i_offset)
                    of pkBool:
                        v.b_value = read_as[bool](buffer, b_i + i_offset)
            return true
        else:
            return false

let s_my_plug_state* = ClapPluginState(save: my_plug_state_save, load: my_plug_state_load)



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