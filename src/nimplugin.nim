import clap
import std/[locks, math, strutils, bitops, tables, algorithm, genasts]
# import jsony
export clap

type
    AutoModuSupport* = object
        base        *: bool
        per_note_id *: bool
        per_key     *: bool
        per_channel *: bool
        per_port    *: bool

converter auto_modu_support_from_bool(b: bool): AutoModuSupport =
    return AutoModuSupport(
        base        : b,
        per_note_id : false,
        per_key     : false,
        per_channel : false,
        per_port    : false
    )

type
    ParameterKind* = enum
        pkFloat,
        pkInt,
        pkBool

    Parameter* = ref object
        name *: string
        path *: string
        case kind *: ParameterKind:
            of pkFloat:
                f_min           *: float64
                f_max           *: float64
                f_default       *: float64
                f_as_value      *: proc (str: string): float64
                f_as_string     *: proc (val: float64): string
                f_remap         *: proc (val: float64): float64
                f_smooth_cutoff *: float64
            of pkInt:
                i_min       *: int64
                i_max       *: int64
                i_default   *: int64
                i_as_value  *: proc (str: string): int64
                i_as_string *: proc (val: int64): string
                i_remap     *: proc (val: int64): int64
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
        automation  *: AutoModuSupport = true
        modulation  *: AutoModuSupport = false

    ParameterValue* = ref object
        #TODO add modulation arrays or whatever
        #TODO - probably doesn't need to be saved/loaded
        #TODO - does need to be handled in event processing
        param *: Parameter
        case kind *: ParameterKind:
            of pkFloat:
                f_raw_value   *: float64
                f_value       *: float64
                f_smooth_coef *: float64
            of pkInt:
                i_raw_value *: int64
                i_value     *: int64
            of pkBool:
                b_value *: bool
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
        # clap pointers
        clap_plugin       *: ptr ClapPlugin
        host              *: ptr ClapHost
        host_latency      *: ptr ClapHostLatency
        host_log          *: ptr ClapHostLog
        host_thread_check *: ptr ClapHostThreadCheck
        host_state        *: ptr ClapHostState
        host_params       *: ptr ClapHostParams
        # managed data
        params         *: seq[Parameter]
        ui_param_data  *: seq[ParameterValue]
        dsp_param_data *: seq[ParameterValue]
        id_map         *: Table[uint32, int]
        name_map       *: Table[string, int]
        save_handlers  *: Table[uint32, proc (plugin: ptr Plugin, data_length: uint32, data: ptr UncheckedArray[byte]): void]
        controls_mutex *: Lock
        # basics
        latency        *: uint32
        sample_rate    *: float64
        desc           *: PluginDesc
        # your data
        # sorry it's a raw pointer, maybe i can change it to a generic without it affecting much of unrelated procs
        # use this for like, your wavetables, filter state variables, etc
        #
        # in the future, i would like to create a multi-process system,
        # in which it contains a seq of self contained processors,
        # each with their own state, start, stop, reset, and process procs, and whatever else
        data           *: pointer
        cb_on_start_processing *: proc (plugin: ptr Plugin): bool
        cb_on_stop_processing  *: proc (plugin: ptr Plugin): void
        cb_on_reset            *: proc (plugin: ptr Plugin): void
        cb_process_block       *: proc (plugin: ptr Plugin, clap_process: ptr ClapProcess, rw_start, rw_end_excluded: int): void
        cb_pre_save            *: proc (plugin: ptr Plugin): void
        cb_data_to_bytes       *: proc (plugin: ptr Plugin): seq[byte]
        cb_data_byte_count     *: proc (plugin: ptr Plugin): int = proc (plugin: ptr Plugin): int = return 0
        cb_data_from_bytes     *: proc (plugin: ptr Plugin, data: seq[byte]): void
        cb_post_load           *: proc (plugin: ptr Plugin): void



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



#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: state and sync
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---



proc cond_set*(c_to, c_from: var ParameterValue): void =
    if c_from.has_changed:
        c_from.has_changed = false
        c_to.has_changed = false
        case c_from.kind:
            of pkFloat:
                c_to.f_raw_value = c_from.f_raw_value
            of pkInt:
                c_to.i_raw_value = c_from.i_raw_value
            of pkBool:
                c_to.b_value = c_from.b_value

proc cond_set_with_event*(c_to, c_from: var ParameterValue, id: ClapID, output: ptr ClapOutputEvents): void =
    if c_from.has_changed:
        c_from.has_changed = false
        c_to.has_changed = false
        var value: float64 = 0.0
        case c_from.kind:
            of pkFloat:
                c_to.f_raw_value = c_from.f_raw_value
                value = c_from.f_raw_value
            of pkInt:
                c_to.i_raw_value = c_from.i_raw_value
                value = float64(c_from.i_raw_value)
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

proc get_byte_at*[T: SomeInteger](val: T, position: int): byte =
    # result = cast[byte]((val shr (position shl 3)) and 0b1111_1111)
    result = cast[byte](val.bitsliced(position ..< position + 8))

template `+`*[T](p: ptr T, off: int): ptr T =
    cast[ptr type(p[])](cast[ByteAddress](p) +% off * sizeof(p[]))

template `+`*[T](p: ptr T, off: uint): ptr T =
    cast[ptr type(p[])](cast[uint](p) + off * uint(sizeof(p[])))

proc `[]=`*[T](p: ptr[T], i: int, x: T) =
    (p + i)[] = x

proc `[]=`*(p: ptr[byte], i: int, x: byte) =
    (p + i)[] = x

# proc `[]=`[T](p: ptr[byte]; i: var uint; x: T) =
#     for j in 0 ..< (T.sizeof):
#         i += 1
#         p[i] = get_byte_at[T](x, uint8(i))

proc `[]=`*[T](p: ptr[byte], i: int, x: T) =
    for j in 0 ..< (T.sizeof):
        p[int(j) + i] = get_byte_at[T](x, int(i))

proc `[]`*[T](p: ptr[T], i: int): T =
    result = (p + i)[]

proc read_as*[T](p: ptr[byte]): T =
    var temp: uint64
    for j in 0 ..< (T.sizeof):
        temp.setMask((p + j)[] shl (j * 8))
    result = cast[T](temp)

proc read_as*[T](data: ptr UncheckedArray[byte], offset: uint = 0): T =
    assert T.sizeof < 8
    var temp: uint64 = 0
    for i in 0 ..< uint(T.sizeof):
        temp = temp or (data[][i + offset] shl (8 * i))
    return cast[T](temp)

proc read_as_ptr*[T](data: ptr UncheckedArray[byte], offset: uint = 0): ptr T =
    var temp = alloc0(T.sizeof)
    copyMem(temp, data + offset, T.sizeof)
    result = cast[ptr T](temp)

proc `->`*[T](i: var int, x: T) =
    i += int(x.sizeof)
proc `<-`*[T](i: var int, x: T) =
    i -= int(x.sizeof)

proc nim_plug_state_save*(clap_plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.} =
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
    if plugin.cb_pre_save != nil:
        plugin.cb_pre_save(plugin)
    var visible_editable_param_count = 0
    for p in plugin.params:
        if (not p.is_hidden) and (not p.is_readonly):
            visible_editable_param_count += 1
    var data_bytes: seq[byte]
    if plugin.cb_data_to_bytes != nil:
        data_bytes = plugin.cb_data_to_bytes(plugin)
    var buf_size = uint32(visible_editable_param_count * (
                                Parameter.id.sizeof +
                                ParameterValue.has_changed.sizeof +
                                ParameterValue.f_raw_value.sizeof
                            ) + 4 + len(data_bytes)) #uint32 4, bool 1, float64 8
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
                    buffer[index] = cast[uint64](v.f_raw_value)
                    index -> v.f_raw_value
                of pkInt:
                    buffer[index] = v.i_raw_value
                    index -> v.i_raw_value
                of pkBool:
                    buffer[index] = cast[uint8](v.b_value)
                    index += int(ParameterValue.f_raw_value.sizeof)
    for data in data_bytes:
        buffer[index] = data
        index += 1
    var written_size = 0
    while written_size < int(buf_size):
        let status = stream.write(stream, buffer + written_size, uint64(int(buf_size) - written_size))
        if status > 0:
            written_size += status
        else:
            return false
    return true

proc nim_plug_state_load*(clap_plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    withLock(plugin.controls_mutex):
        var buf_size: uint32 = 0
        if stream.read(stream, addr buf_size, uint64(uint32.sizeof)) > 0:
            var buffer: ptr[byte] = cast[ptr[byte]](alloc0(int(buf_size) - uint32.sizeof))
            var read_size = 0
            while read_size < int(buf_size):
                let status = stream.read(stream, buffer + read_size, uint64(int(buf_size) - read_size))
                if status >= 0:
                    read_size += status
                elif status == 0:
                    break
                else:
                    return false
            var data_byte_count = plugin.cb_data_byte_count(plugin)
            for b_i in countup(0, int(buf_size) - data_byte_count, (
                                Parameter.id.sizeof +
                                ParameterValue.has_changed.sizeof +
                                ParameterValue.f_raw_value.sizeof
                            )):
                var i_offset = 0
                var p_i = plugin.id_map[read_as[uint32](buffer + b_i)]
                var v = plugin.ui_param_data[p_i]
                var p = plugin.params[p_i]
                i_offset += uint32.sizeof
                v.has_changed = read_as[bool](buffer + b_i + i_offset)
                i_offset += bool.sizeof
                case v.kind:
                    of pkFloat:
                        v.f_raw_value = read_as[float64](buffer + b_i + i_offset)
                        v.f_value = if p.f_remap != nil:
                                                p.f_remap(v.f_raw_value)
                                            else:
                                                v.f_raw_value
                    of pkInt:
                        v.i_raw_value = read_as[int64](buffer + b_i + i_offset)
                    of pkBool:
                        v.b_value = read_as[bool](buffer + b_i + i_offset)
            var data_bytes: seq[byte]
            for i in int(buf_size) - data_byte_count ..< int(buf_size):
                data_bytes.add(read_as[byte](buffer + i))
            if plugin.cb_data_from_bytes != nil:
                plugin.cb_data_from_bytes(plugin, data_bytes)
            if plugin.cb_post_load != nil:
                plugin.cb_post_load(plugin)
            return true
        else:
            return false

## tree of memory blobs
##
## key uint32
## length uint32
## data
##
## key 0 is a container of other memory blobs, which can form a tree
## key 1 is a parameter, handled by the library
##
## other keys can be assigned per plugin, to allow for specialized handling, such as grouping data for a processor graph

proc nim_plug_load_handle_tree*(plugin: ptr Plugin, data_length: uint32, data: ptr UncheckedArray[byte]): void =
    var counter: uint32 = 0
    while counter < data_length:
        var key: uint32 = read_as[uint32](data, counter)
        counter += uint32(uint32.sizeof)
        var length: uint32 = read_as[uint32](data, counter)
        counter += uint32(uint32.sizeof)
        if counter + length < data_length:
            plugin.save_handlers[key](plugin, length, data + counter)
            counter += length

proc nim_plug_load_handle_parameter*(plugin: ptr Plugin, data_length: uint32, data: ptr UncheckedArray[byte]): void =
    var counter = 0'u
    if data_length > uint32(uint8.sizeof + uint32.sizeof):
        var kind: uint8 = read_as[uint8](data, counter)
        counter += uint(uint8.sizeof)
        var id: uint32 = read_as[uint32](data, counter)
        counter += uint(uint32.sizeof)
        var p_index = plugin.id_map[id]
        var v = plugin.ui_param_data[p_index]
        var p = plugin.params[p_index]
        var contained_value: bool = false
        case kind:
            of 0: # float, 8 bytes
                if data_length > uint32(uint8.sizeof + uint32.sizeof + float64.sizeof):
                    contained_value = true
                    case p.kind:
                        of pkFloat: # save and plugin data match
                            v.f_raw_value = read_as[float64](data, counter)
                            v.f_value = if p.f_remap != nil:
                                            p.f_remap(v.f_raw_value)
                                        else:
                                            v.f_raw_value
                        of pkInt: # saved a float, loaded as int
                            v.i_raw_value = int64(read_as[float64](data, counter))
                            v.i_value = if p.i_remap != nil:
                                            p.i_remap(v.i_raw_value)
                                        else:
                                            v.i_raw_value
                        of pkBool: # saved a float, loaded as bool
                            v.b_value = read_as[float64](data, counter) >= 0.5
            of 1: # int, 8 bytes
                if data_length > uint32(uint8.sizeof + uint32.sizeof + int64.sizeof):
                    contained_value = true
                    case p.kind:
                        of pkFloat: # saved an int, loaded as float
                            v.f_raw_value = float64(read_as[int64](data, counter))
                            v.f_value = if p.f_remap != nil:
                                            p.f_remap(v.f_raw_value)
                                        else:
                                            v.f_raw_value
                        of pkInt: # save and plugin data match
                            v.i_raw_value = read_as[int64](data, counter)
                            v.i_value = if p.i_remap != nil:
                                            p.i_remap(v.i_raw_value)
                                        else:
                                            v.i_raw_value
                        of pkBool: # saved an int, loaded as bool
                            v.b_value = read_as[int64](data, counter) >= 1
            of 2: # bool, 1 byte
                if data_length > uint32(uint8.sizeof + uint32.sizeof + uint8.sizeof):
                    contained_value = true
                    case p.kind:
                        of pkBool: # save and plugin data match
                            v.b_value = countSetBits(read_as[uint8](data, counter)) > 4
                        else: # saved a bool, loaded as something else
                            # i'm not sure you can get anything meaningful here
                            contained_value = false
            else:
                discard
        if not contained_value:
            # the data block wasn't long enough to contain meaningful data, so just set defaults
            case p.kind:
                of pkFloat:
                    var remapped = if p.f_remap != nil:
                                    p.f_remap(p.f_default)
                                else:
                                    p.f_default
                    v.f_raw_value = p.f_default
                    v.f_value     = remapped
                of pkInt:
                    var remapped = if p.i_remap != nil:
                                    p.i_remap(p.i_default)
                                else:
                                    p.i_default
                    v.i_raw_value = p.i_default
                    v.i_value     = remapped
                of pkBool:
                    v.b_value = p.b_default

let s_nim_plug_state* = ClapPluginState(save: nim_plug_state_save, load: nim_plug_state_load)



#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: process
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---



proc lerp*(x, y, mix: float32): float32 =
    result = (y - x) * mix + x

const pi *: float64 = 3.1415926535897932384626433832795

# based on reaktor one pole lowpass coef calculation
proc onepole_lp_coef*(freq: float64, sr: float64): float64 =
    var input: float64 = min(0.5 * pi, max(0.001, freq) * (pi / sr));
    var tanapprox: float64 = (((0.0388452 - 0.0896638 * input) * input + 1.00005) * input) /
                            ((0.0404318 - 0.430871 * input) * input + 1);
    return tanapprox / (tanapprox + 1);

# based on reaktor one pole lowpass
proc onepole_lp*(last: var float64, coef: float64, src: float64): float64 =
    var delta_scaled: float64 = (src - last) * coef;
    var dst: float64 = delta_scaled + last;
    last = delta_scaled + dst;
    return dst;

proc simple_lp_coef*(freq: float64, sr: float64): float64 =
    var w: float64 = (2 * pi * freq) / sr;
    var twomcos: float64 = 2 - cos(w);
    return 1 - (twomcos - sqrt(twomcos * twomcos - 1));

proc simple_lp*(smooth: var float64, coef: float64, next: float64): var float64 =
    smooth += coef * (next - smooth)
    return smooth

proc nim_plug_start_processing*(clap_plugin: ptr ClapPlugin): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if plugin.cb_on_start_processing != nil:
        return plugin.cb_on_start_processing(plugin)
    return true

proc nim_plug_stop_processing*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if plugin.cb_on_stop_processing != nil:
        plugin.cb_on_stop_processing(plugin)

proc nim_plug_reset*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if plugin.cb_on_reset != nil:
        plugin.cb_on_reset(plugin)

proc nim_plug_process_event*(plugin: ptr Plugin, event: ptr ClapEventUnion): void {.cdecl.} =
    # myplug.dsp_controls.level = float32(event.kindParamValMod.val_amt)
    if event.kindParamValMod.header.space_id == 0:
        case event.kindParamValMod.header.event_type: # kindParamValMod for both, as the objects are identical
            of cetPARAM_VALUE: # actual knob changes or automation
                withLock(plugin.controls_mutex):
                    let index = plugin.id_map[uint32(event.kindParamValMod.param_id)]
                    var param_data = plugin.dsp_param_data[index]
                    var param = plugin.params[index]
                    case param.kind:
                        of pkFloat:
                            param_data.f_raw_value = event.kindParamValMod.val_amt
                            param_data.f_value = simple_lp(
                                                            param_data.f_value,
                                                            param_data.f_smooth_coef,
                                                            if param.f_remap != nil:
                                                                param.f_remap(event.kindParamValMod.val_amt)
                                                            else:
                                                                event.kindParamValMod.val_amt)
                            param_data.has_changed = true # maybe set up converters to set this and automatically handle conversion based on kind
                        of pkInt:
                            param_data.i_raw_value = if param.i_remap != nil:
                                                    param.i_remap(int64(event.kindParamValMod.val_amt))
                                                else:
                                                    int64(event.kindParamValMod.val_amt)
                            param_data.has_changed = true
                        of pkBool:
                            param_data.b_value = event.kindParamValMod.val_amt > 0.5
                            param_data.has_changed = true
            of cetPARAM_MOD: # per voice modulation
                discard
            else:
                discard

proc nim_plug_process*(clap_plugin: ptr ClapPlugin, process: ptr ClapProcess): ClapProcessStatus {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)

    plugin.sync_ui_to_dsp(process.out_events)

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

            # if event.kindNote.header.event_type == cetPARAM_VALUE:
            #     event.kindParamValMod.val_amt = 1
            nim_plug_process_event(plugin, event)
            event_idx += 1

            if event_idx == num_events:
                next_event_frame = num_frames
                break

        plugin.cb_process_block(plugin, process, int(i), int(next_event_frame))
        i = next_event_frame
        # while i < next_event_frame:
        #     discard plugin.audio_data.smoothed_level
        #                 .simple_lp(plugin.smooth_coef, db_af(plugin.dsp_controls.level))
        #     discard plugin.audio_data.smoothed_flip
        #                 .simple_lp(plugin.smooth_coef, plugin.dsp_controls.flip)
        #     discard plugin.audio_data.smoothed_rotate
        #                 .simple_lp(plugin.smooth_coef, pi * plugin.dsp_controls.rotate)

        #     let in_l: float32 = process.audio_inputs[0].data32[0][i]
        #     let in_r: float32 = process.audio_inputs[0].data32[1][i]

        #     # let out_l = in_r * 0.5
        #     # let out_r = in_l
        #     var scaled_l = plugin.audio_data.smoothed_level * in_l
        #     var scaled_r = plugin.audio_data.smoothed_level * in_r
        #     var flipped_l = lerp(scaled_l, scaled_r, plugin.audio_data.smoothed_flip)
        #     var flipped_r = lerp(scaled_r, scaled_l, plugin.audio_data.smoothed_flip)
        #     let a_cos: float32 = cos(plugin.audio_data.smoothed_rotate)
        #     let a_sin: float32 = sin(plugin.audio_data.smoothed_rotate)
        #     var out_l = flipped_l * a_cos + flipped_r * a_sin
        #     var out_r = flipped_r * a_cos - flipped_l * a_sin

        #     process.audio_outputs[0].data32[0][i] = out_l
        #     process.audio_outputs[0].data32[1][i] = out_r

        #     i += 1
    return cpsCONTINUE



#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: params
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---



proc nim_plug_params_count*(clap_plugin: ptr ClapPlugin): uint32 {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    return uint32(len(plugin.params))

proc nim_plug_params_get_info*(clap_plugin: ptr ClapPlugin, index: uint32, information: ptr ClapParamInfo): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    # if index >= uint32(len(plugin.params)):
    #     return false
    # else:
    if index notin plugin.id_map:
        return false
    else:
        var param = plugin.params[plugin.id_map[index]]
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
            id            : ClapID(param.id),
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

proc bool_to_float*(b: bool): float64 =
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
                                plugin.ui_param_data[index].f_raw_value
                            of pkInt:
                                float64(plugin.ui_param_data[index].i_raw_value)
                            of pkBool:
                                bool_to_float(plugin.ui_param_data[index].b_value)
                    else:
                        case plugin.dsp_param_data[index].kind:
                            of pkFloat:
                                plugin.dsp_param_data[index].f_raw_value
                            of pkInt:
                                float64(plugin.dsp_param_data[index].i_raw_value)
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

proc simple_str_bool*(s: string): bool =
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

proc nim_plug_params_flush*(clap_plugin: ptr ClapPlugin, input: ptr ClapInputEvents, output: ptr ClapOutputEvents): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    let event_count = input.size(input)
    sync_ui_to_dsp(plugin, output)
    for i in 0 ..< event_count:
        nim_plug_process_event(plugin, input.get(input, i))

let s_nim_plug_params * = ClapPluginParams(
        count         : nim_plug_params_count,
        get_info      : nim_plug_params_get_info,
        get_value     : nim_plug_params_get_value,
        value_to_text : nim_plug_params_value_to_text,
        text_to_value : nim_plug_params_text_to_value,
        flush         : nim_plug_params_flush
    )



#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: create params seq
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---



#TODO when modulation is supported, add modulation support input

proc newFloatParameter*(
        name            : string,
        min             : float64,
        max             : float64,
        default         : float64,
        id              : uint32,
        smooth_cutoff   : float64 = 10.0,
        as_value        : proc (str: string): float64 = nil,
        as_string       : proc (val: float64): string = nil,
        remap           : proc (val: float64): float64 = nil,
        path            : string = "",
        is_periodic     : bool = false,
        is_hidden       : bool = false,
        is_readonly     : bool = false,
        is_bypass       : bool = false,
        is_enum         : bool = false,
        req_process     : bool = true,
        automation      : AutoModuSupport = true): Parameter =
    return Parameter(
        name            : name,
        path            : path,
        kind            : pkFloat,
        f_min           : min,
        f_max           : max,
        f_default       : default,
        f_as_value      : as_value,
        f_as_string     : as_string,
        f_remap         : remap,
        f_smooth_cutoff : smooth_cutoff,
        id              : id,
        is_periodic     : is_periodic,
        is_hidden       : is_hidden,
        is_readonly     : is_readonly,
        is_bypass       : is_bypass,
        is_enum         : is_enum,
        req_process     : req_process,
        automation      : automation
    )

proc newIntParameter*(
        name            : string,
        min             : int64,
        max             : int64,
        default         : int64,
        id              : uint32,
        as_value        : proc (str: string): int64 = nil,
        as_string       : proc (val: int64): string = nil,
        remap           : proc (val: int64): int64 = nil,
        path            : string = "",
        is_periodic     : bool = false,
        is_hidden       : bool = false,
        is_readonly     : bool = false,
        is_bypass       : bool = false,
        is_enum         : bool = false,
        req_process     : bool = true,
        automation      : AutoModuSupport = true): Parameter =
    return Parameter(
        name            : name,
        path            : path,
        kind            : pkInt,
        i_min           : min,
        i_max           : max,
        i_default       : default,
        i_as_value      : as_value,
        i_as_string     : as_string,
        i_remap         : remap,
        id              : id,
        is_periodic     : is_periodic,
        is_hidden       : is_hidden,
        is_readonly     : is_readonly,
        is_bypass       : is_bypass,
        is_enum         : is_enum,
        req_process     : req_process,
        automation      : automation
    )

proc newBoolParameter*(
        name            : string,
        default         : bool,
        id              : uint32,
        true_str        : string = "True",
        false_str       : string = "False",
        path            : string = "",
        is_periodic     : bool = false,
        is_hidden       : bool = false,
        is_readonly     : bool = false,
        is_bypass       : bool = false,
        is_enum         : bool = true,
        req_process     : bool = true,
        automation      : AutoModuSupport = true): Parameter =
    return Parameter(
        name            : name,
        path            : path,
        kind            : pkBool,
        b_default       : default,
        true_str        : true_str,
        false_str       : false_str,
        id              : id,
        is_periodic     : is_periodic,
        is_hidden       : is_hidden,
        is_readonly     : is_readonly,
        is_bypass       : is_bypass,
        is_enum         : is_enum,
        req_process     : req_process,
        automation      : automation
    )

proc repeat*(
        param : Parameter,
        name  : seq[string],
        id    : seq[uint32]
        ): seq[Parameter] =
    if len(name) == len(id):
        for i in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[i]
            p.id = id[i]
            result.add(p)
    elif len(id) == 1:
        for i in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[i]
            p.id = id[0] + uint32(i)
            result.add(p)
    elif len(name) == 1:
        for i in 0 ..< len(id):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[0] & " " & $(i + 1)
            p.id = id[i]
            result.add(p)

proc repeat*(
        param  : Parameter,
        repeat : int,
        name   : seq[string],
        id     : uint32
        ): seq[Parameter] =
    for i in 0 ..< repeat:
        for j in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[j] & " " & $(j + 1)
            p.id = id + uint32(j) + uint32(i * len(name))
            result.add(p)

proc repeat_parameter*(
        param  : Parameter,
        repeat : int,
        name   : seq[string],
        id     : seq[uint32]
        ): seq[Parameter] =
    assert repeat * len(name) == len(id)
    for i in 0 ..< repeat:
        for j in 0 ..< len(name):
            var p: Parameter
            p.deepCopy(param)
            p.name = name[j] & " " & $(j + 1)
            p.id = id[j + i * len(name)]
            result.add(p)

proc id_from_index*(params: var seq[Parameter]): void =
    for i in 0 ..< len(params):
        params[i].id = uint32(i)

proc param_id_cmp*(p1, p2: Parameter): int =
    cmp(int(p1.id), int(p2.id))

proc sort_by_id*(params: var seq[Parameter]): void =
    params.sort(param_id_cmp)

# proc fill_ids*(params: var seq[Parameter]): void =
#     var ids: seq[uint32]
#     for p in params:
#         ids.add(p.id)
#     ids.sort()
#     var new_ids: seq[uint32]
#     var last: uint32 = 0
#     for i in ids:
#         assert i != last
#         if i - last > 1:
#             for j in 0 ..< (i - last):
#                 new_ids.add(i + uint32(j))
#     for n in new_ids:
#         params.add newBoolParameter(
#             name: "hidden"
#         )

proc id_table*(params: seq[Parameter]): Table[uint32, int] =
    for i in 0 ..< len(params):
        result[params[i].id] = i



#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# MARK: creation, entry, activation, deactivation
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#93F6E9 --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---



proc convert_plugin_descriptor*(desc: PluginDesc): ClapPluginDescriptor =
    result = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major:    CLAP_VERSION_MAJOR,
            minor:    CLAP_VERSION_MINOR,
            revision: CLAP_VERSION_REVISION),
        id: cstring(desc.id),
        name: cstring(desc.name),
        vendor: cstring(desc.vendor),
        url: cstring(desc.url),
        manual_url: cstring(desc.manual_url),
        support_url: cstring(desc.support_url),
        version: cstring(desc.version),
        description: cstring(desc.description),
        features: allocCStringArray(desc.features))

proc nim_plug_get_extension*(clap_plugin: ptr ClapPlugin, id: cstring): pointer {.cdecl.} =
    case id:
        of CLAP_EXT_LATENCY:
            return addr s_nim_plug_latency
        of CLAP_EXT_AUDIO_PORTS:
            return addr s_nim_plug_audio_ports
        of CLAP_EXT_NOTE_PORTS:
            return addr s_nim_plug_note_ports
        of CLAP_EXT_STATE:
            return addr s_nim_plug_state
        of CLAP_EXT_PARAMS:
            return addr s_nim_plug_params


# var nim_plug_desc   *: PluginDesc
var nim_plug_desc   *: ClapPluginDescriptor
var nim_plug_params *: seq[Parameter]
var nim_plug_id_map *: Table[uint32, int]
var cb_process_block *: proc (plugin: ptr Plugin, clap_process: ptr ClapProcess, rw_start, rw_end_excluded: int): void

var nim_plug_user_data *: pointer = nil

var cb_on_start_processing *: proc (plugin: ptr Plugin): bool = nil
var cb_on_stop_processing  *: proc (plugin: ptr Plugin): void = nil
var cb_on_reset            *: proc (plugin: ptr Plugin): void = nil
var cb_pre_save            *: proc (plugin: ptr Plugin): void = nil
var cb_data_to_bytes       *: proc (plugin: ptr Plugin): seq[byte] = nil
var cb_data_byte_count     *: proc (plugin: ptr Plugin): int = proc (plugin: ptr Plugin): int = return 0
var cb_data_from_bytes     *: proc (plugin: ptr Plugin, data: seq[byte]): void = nil
var cb_post_load           *: proc (plugin: ptr Plugin): void = nil

var cb_init           *: proc (plugin: ptr Plugin): void = nil
var cb_destroy        *: proc (plugin: ptr Plugin): void = nil
var cb_activate       *: proc (plugin: ptr Plugin, sample_rate: float64, min_frames_count: uint32, max_frames_count: uint32): void = nil
var cb_deactivate     *: proc (plugin: ptr Plugin): void = nil
var cb_on_main_thread *: proc (plugin: ptr Plugin): void = nil
var cb_create         *: proc (plugin: ptr Plugin, host: ptr ClapHost): void = nil

# let s_nim_plug_desc* = convert_plugin_descriptor(nim_plug_desc)

proc nim_plug_init*(clap_plugin: ptr ClapPlugin): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    plugin.host_log          = cast[ptr ClapHostLog         ](plugin.host.get_extension(plugin.host, CLAP_EXT_LOG          ))
    plugin.host_thread_check = cast[ptr ClapHostThreadCheck ](plugin.host.get_extension(plugin.host, CLAP_EXT_THREAD_CHECK ))
    plugin.host_latency      = cast[ptr ClapHostLatency     ](plugin.host.get_extension(plugin.host, CLAP_EXT_LATENCY      ))
    plugin.host_state        = cast[ptr ClapHostState       ](plugin.host.get_extension(plugin.host, CLAP_EXT_STATE        ))
    plugin.host_params       = cast[ptr ClapHostParams      ](plugin.host.get_extension(plugin.host, CLAP_EXT_PARAMS       ))
    for i in 0 ..< len(plugin.params):
        var p = plugin.params[i]
        case p.kind:
            of pkFloat:
                var remapped = if p.f_remap != nil:
                                p.f_remap(p.f_default)
                            else:
                                p.f_default
                plugin.dsp_param_data[i].f_raw_value = p.f_default
                plugin.dsp_param_data[i].f_value     = remapped
                plugin.ui_param_data[i].f_raw_value = p.f_default
                plugin.ui_param_data[i].f_value     = remapped
            of pkInt:
                var remapped = if p.i_remap != nil:
                                p.i_remap(p.i_default)
                            else:
                                p.i_default
                plugin.dsp_param_data[i].i_raw_value = p.i_default
                plugin.dsp_param_data[i].i_value     = remapped
                plugin.ui_param_data[i].i_raw_value = p.i_default
                plugin.ui_param_data[i].i_value     = remapped
            of pkBool:
                plugin.dsp_param_data[i].b_value = plugin.params[i].b_default
                plugin.ui_param_data[i].b_value = plugin.params[i].b_default
    initLock(plugin.controls_mutex)
    if cb_init != nil:
        cb_init(plugin)
    return true

proc nim_plug_destroy*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if cb_destroy != nil:
        cb_destroy(plugin)
    dealloc(plugin)

proc nim_plug_activate*(clap_plugin: ptr ClapPlugin,
                        sample_rate: float64,
                        min_frames_count: uint32,
                        max_frames_count: uint32): bool {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    plugin.sample_rate = sample_rate
    for i in 0 ..< len(plugin.params):
        if plugin.params[i].kind == pkFloat:
            var coef = simple_lp_coef(plugin.params[i].f_smooth_cutoff, sample_rate)
            plugin.dsp_param_data[i].f_smooth_coef = coef
            plugin.ui_param_data[i].f_smooth_coef = coef
    if cb_activate != nil:
        cb_activate(plugin, sample_rate, min_frames_count, max_frames_count)
    return true

proc nim_plug_deactivate*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if cb_deactivate != nil:
        cb_deactivate(plugin)

proc nim_plug_on_main_thread*(clap_plugin: ptr ClapPlugin): void {.cdecl.} =
    var plugin = cast[ptr Plugin](clap_plugin.plugin_data)
    if cb_on_main_thread != nil:
        cb_on_main_thread(plugin)

proc nim_plug_create*(host: ptr ClapHost): ptr ClapPlugin {.cdecl.} =
    var plugin = cast[ptr Plugin](alloc0(Plugin.sizeof))
    plugin.host = host
    plugin.clap_plugin = cast[ptr ClapPlugin](alloc0(ClapPlugin.sizeof)) # remove if changed to not a pointer
    plugin.clap_plugin.desc = addr nim_plug_desc
    plugin.clap_plugin.plugin_data = plugin
    plugin.clap_plugin.init = nim_plug_init
    plugin.clap_plugin.destroy = nim_plug_destroy
    plugin.clap_plugin.activate = nim_plug_activate
    plugin.clap_plugin.deactivate = nim_plug_deactivate
    plugin.clap_plugin.start_processing = nim_plug_start_processing
    plugin.clap_plugin.stop_processing = nim_plug_stop_processing
    plugin.clap_plugin.reset = nim_plug_reset
    plugin.clap_plugin.process = nim_plug_process
    plugin.clap_plugin.get_extension = nim_plug_get_extension
    plugin.clap_plugin.on_main_thread = nim_plug_on_main_thread
    plugin.params = nim_plug_params
    plugin.id_map = nim_plug_id_map
    plugin.dsp_param_data = @[]
    plugin.ui_param_data = @[]
    for i in 0 ..< len(plugin.params):
        plugin.dsp_param_data.add(ParameterValue(
            param: plugin.params[i],
            kind:  plugin.params[i].kind
        ))
        plugin.ui_param_data.add(ParameterValue(
            param: plugin.params[i],
            kind:  plugin.params[i].kind
        ))
    plugin.data                   = nim_plug_user_data
    plugin.cb_on_start_processing = cb_on_start_processing
    plugin.cb_on_stop_processing  = cb_on_stop_processing
    plugin.cb_on_reset            = cb_on_reset
    plugin.cb_process_block       = cb_process_block
    plugin.cb_pre_save            = cb_pre_save
    plugin.cb_data_to_bytes       = cb_data_to_bytes
    plugin.cb_data_byte_count     = cb_data_byte_count
    plugin.cb_data_from_bytes     = cb_data_from_bytes
    plugin.cb_post_load           = cb_post_load
    if cb_create != nil:
        cb_create(plugin, host)
    return plugin.clap_plugin
    # return addr plugin.clap_plugin # if it wasn't a pointer

type
    ClapDescCreate* = object
        desc *: ptr ClapPluginDescriptor
        create *: proc (host: ptr ClapHost): ptr ClapPlugin {.cdecl.}

const plugin_count*: uint32 = 1

let s_plugins: array[plugin_count, ClapDescCreate] = [
    ClapDescCreate(desc: addr nim_plug_desc, create: nim_plug_create)
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
