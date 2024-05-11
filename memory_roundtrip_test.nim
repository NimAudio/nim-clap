import src/nimplugin

import std/[tables]

var params*: seq[Parameter] = @[]

params.add(newBoolParameter("bool", true, uint32(0)))

## if just one bool, saved buffer should be
## 0 * 4 (uint32) * 4 (four of them) (version)
## 0 0 0 0 (tree, uint32)
## 0 0 0 0 0 0 0 18 (tree length)
## 0 0 0 1 (parameter, uint32)
## 0 0 0 0 0 0 0 6 (param length, uint64 since it's not part of the data block)
## 0 0 0 0 (param id, uint32)
## 2 (bool)
## 255 (true)

# params.add(newIntParameter("int", -1, 53, 31, uint32(1)))
# params.add(newFloatParameter("float", 0.0, 1.0, 0.33333333, uint32(2), 10))

for i in 1 .. 10:
    if i mod 3 == 0:
        params.add(newIntParameter($i & "int", -i, i, i, uint32(i)))
    else:
        params.add(newFloatParameter($i & "float", 0.0, float(i), 0.3333 + 0.01 * float(i), uint32(i), 10))

var id_map* = params.id_table()

var save_handlers: Table[uint32, proc (plugin: ptr Plugin, data: ptr UncheckedArray[byte], data_length: uint64, offset: uint64): void]
save_handlers[0'u32] = nim_plug_load_handle_tree
save_handlers[1'u32] = nim_plug_load_handle_parameter

var plug: ptr Plugin = cast[ptr Plugin](alloc0(Plugin.sizeof))
plug.params = params
plug.id_map = id_map
plug.save_handlers = save_handlers
plug.dsp_param_data = @[]
plug.ui_param_data = @[]
for i in 0 ..< len(plug.params):
    plug.dsp_param_data.add(ParameterValue(
        param: plug.params[i],
        kind:  plug.params[i].kind
    ))
    plug.ui_param_data.add(ParameterValue(
        param: plug.params[i],
        kind:  plug.params[i].kind
    ))
for i in 0 ..< len(plug.params):
    var p = plug.params[i]
    case p.kind:
        of pkFloat:
            var remapped = if p.f_remap != nil:
                            p.f_remap(p.f_default)
                        else:
                            p.f_default
            plug.dsp_param_data[i].f_raw_value = p.f_default
            plug.dsp_param_data[i].f_value     = remapped
            plug.ui_param_data[i].f_raw_value = p.f_default
            plug.ui_param_data[i].f_value     = remapped
        of pkInt:
            var remapped = if p.i_remap != nil:
                            p.i_remap(p.i_default)
                        else:
                            p.i_default
            plug.dsp_param_data[i].i_raw_value = p.i_default
            plug.dsp_param_data[i].i_value     = remapped
            plug.ui_param_data[i].i_raw_value = p.i_default
            plug.ui_param_data[i].i_value     = remapped
        of pkBool:
            plug.dsp_param_data[i].b_value = plug.params[i].b_default
            plug.ui_param_data[i].b_value = plug.params[i].b_default

var buf_size = nim_plug_save_param_tree_size(plug) + 16 # version
echo(buf_size)
var buffer: ptr UncheckedArray[byte] = cast[ptr UncheckedArray[byte]](alloc0(buf_size))

nim_plug_save_main(plug, buffer)

var plug_read: ptr Plugin = cast[ptr Plugin](alloc0(Plugin.sizeof))
plug_read.params = params
plug_read.id_map = id_map
plug_read.save_handlers = save_handlers
plug_read.dsp_param_data = @[]
plug_read.ui_param_data = @[]
for i in 0 ..< len(plug_read.params):
    plug_read.dsp_param_data.add(ParameterValue(
        param: plug_read.params[i],
        kind:  plug_read.params[i].kind
    ))
    plug_read.ui_param_data.add(ParameterValue(
        param: plug_read.params[i],
        kind:  plug_read.params[i].kind
    ))
discard nim_plug_load_main(plug_read, buffer, buf_size)

for i in 0 ..< len(plug.params):
    echo "--"
    case plug.params[i].kind:
        of pkFloat:
            echo plug.ui_param_data[i].f_raw_value
            echo plug_read.ui_param_data[i].f_raw_value
            echo (plug.ui_param_data[i].f_raw_value - plug_read.ui_param_data[i].f_raw_value) * 1000
        of pkInt:
            echo plug.ui_param_data[i].i_raw_value
            echo plug_read.ui_param_data[i].i_raw_value
            echo plug.ui_param_data[i].i_raw_value - plug_read.ui_param_data[i].i_raw_value
        of pkBool:
            echo plug.ui_param_data[i].b_value
            echo plug_read.ui_param_data[i].b_value
            echo plug.ui_param_data[i].b_value == plug_read.ui_param_data[i].b_value
    echo "--"

for i in 0 ..< buf_size:
    stdout.write(buffer[i])
    stdout.write(" ")

# echo(read_as[uint64](buffer, 20))