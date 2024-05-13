import src/nimplugin
import std/[locks, math, strutils]

# proc db_af*(db: float64): float64 =
#     result = pow(10, 0.05 * db)

# proc af_db*(af: float64): float64 =
#     result = 20 * log10(af)

var p_gain * = newFloatParameter(
    "Level",
    -48,
    24,
    0,
    0'u32,
    smLerp,
    100,
    proc (s: string): float64 = float64(parseFloat(s.strip().split(" ")[0])),
    proc (x: float64): string = x.formatBiggestFloat(ffDecimal, 6) & " db",
    db_af
)
var p_flip * = newFloatParameter(
    "Flip",
    0,
    1,
    0,
    1'u32,
    smLerp,
    100
)
var p_rotate * = newFloatParameter(
    "Rotate",
    -1,
    1,
    0,
    2'u32,
    smLerp,
    100,
    remap = proc (x: float64): float64 = PI * x
)

var params * = @[p_gain, p_flip, p_rotate]
var id_map * = params.id_table()

let desc * = PluginDesc(
    id          : "com.nimclap.example2",
    name        : "nim-clap abstraction layer example plugin",
    vendor      : "nim-clap",
    url         : "https://www.github.com/morganholly/nim-clap",
    manual_url  : "https://www.github.com/morganholly/nim-clap",
    support_url : "https://www.github.com/morganholly/nim-clap",
    version     : "0.1",
    description : "example effect plugin",
    features    : @[CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
                    CLAP_PLUGIN_FEATURE_EQUALIZER,
                    CLAP_PLUGIN_FEATURE_DISTORTION,
                    CLAP_PLUGIN_FEATURE_STEREO]
)

proc lerp*(x, y, mix: float32): float32 =
    result = (y - x) * mix + x

proc process*(plugin: ptr Plugin, in_left, in_right: float64, out_left, out_right: var float64, latency: uint32): void =
    var scaled_l = plugin.dsp_param_data[0].f_value * in_left
    var scaled_r = plugin.dsp_param_data[0].f_value * in_right
    var flipped_l = lerp(scaled_l, scaled_r, plugin.dsp_param_data[1].f_value)
    var flipped_r = lerp(scaled_r, scaled_l, plugin.dsp_param_data[1].f_value)
    let a_cos: float32 = cos(plugin.dsp_param_data[2].f_value)
    let a_sin: float32 = sin(plugin.dsp_param_data[2].f_value)
    out_left = flipped_l * a_cos + flipped_r * a_sin
    out_right = flipped_r * a_cos - flipped_l * a_sin

let features*: cstringArray = allocCStringArray([CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
                                                CLAP_PLUGIN_FEATURE_EQUALIZER,
                                                CLAP_PLUGIN_FEATURE_DISTORTION,
                                                CLAP_PLUGIN_FEATURE_STEREO])

let clap_desc* = ClapPluginDescriptor(
        clap_version: ClapVersion(
            major    : CLAP_VERSION_MAJOR,
            minor    : CLAP_VERSION_MINOR,
            revision : CLAP_VERSION_REVISION),
        id          : "com.nimclap.example2",
        name        : "nim-clap abstraction layer example plugin",
        vendor      : "nim-clap",
        url         : "https://www.github.com/morganholly/nim-clap",
        manual_url  : "https://www.github.com/morganholly/nim-clap",
        support_url : "https://www.github.com/morganholly/nim-clap",
        version     : "0.1",
        description : "example effect plugin",
        features    : features)

# nim_plug_desc    = desc
nim_plug_desc     = clap_desc
nim_plug_params   = params
nim_plug_id_map   = id_map
cb_process_sample = process