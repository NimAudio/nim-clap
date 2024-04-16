const
    CLAP_NAME_SIZE* = 256
    CLAP_PATH_SIZE* = 1024

type
    ClapID* = distinct uint32

    ClapVersion* = ClapVersionT
    ClapVersionT* = object
        major    *: uint32
        minor    *: uint32
        revision *: uint32

const
    CLAP_VERSION_MAJOR    *: uint32 = 1
    CLAP_VERSION_MINOR    *: uint32 = 2
    CLAP_VERSION_REVISION *: uint32 = 0
    CLAP_VERSION_INIT     * = ClapVersion(major: CLAP_VERSION_MAJOR,
                                            minor: CLAP_VERSION_MINOR,
                                            revision: CLAP_VERSION_REVISION)

const CLAP_INVALID_ID* = high(ClapID)

const CLAP_CORE_EVENT_SPACE_ID *: uint16 = 0

const
    CLAP_PLUGIN_FEATURE_INSTRUMENT        *: string = "instrument"
    CLAP_PLUGIN_FEATURE_AUDIO_EFFECT      *: string = "audio-effect"
    CLAP_PLUGIN_FEATURE_NOTE_EFFECT       *: string = "note-effect"
    CLAP_PLUGIN_FEATURE_NOTE_DETECTOR     *: string = "note-detector"
    CLAP_PLUGIN_FEATURE_ANALYZER          *: string = "analyzer"
    CLAP_PLUGIN_FEATURE_SYNTHESIZER       *: string = "synthesizer"
    CLAP_PLUGIN_FEATURE_SAMPLER           *: string = "sampler"
    CLAP_PLUGIN_FEATURE_DRUM              *: string = "drum"
    CLAP_PLUGIN_FEATURE_DRUM_MACHINE      *: string = "drum-machine"
    CLAP_PLUGIN_FEATURE_FILTER            *: string = "filter"
    CLAP_PLUGIN_FEATURE_PHASER            *: string = "phaser"
    CLAP_PLUGIN_FEATURE_EQUALIZER         *: string = "equalizer"
    CLAP_PLUGIN_FEATURE_DEESSER           *: string = "de-esser"
    CLAP_PLUGIN_FEATURE_PHASE_VOCODER     *: string = "phase-vocoder"
    CLAP_PLUGIN_FEATURE_GRANULAR          *: string = "granular"
    CLAP_PLUGIN_FEATURE_FREQUENCY_SHIFTER *: string = "frequency-shifter"
    CLAP_PLUGIN_FEATURE_PITCH_SHIFTER     *: string = "pitch-shifter"
    CLAP_PLUGIN_FEATURE_DISTORTION        *: string = "distortion"
    CLAP_PLUGIN_FEATURE_TRANSIENT_SHAPER  *: string = "transient-shaper"
    CLAP_PLUGIN_FEATURE_COMPRESSOR        *: string = "compressor"
    CLAP_PLUGIN_FEATURE_EXPANDER          *: string = "expander"
    CLAP_PLUGIN_FEATURE_GATE              *: string = "gate"
    CLAP_PLUGIN_FEATURE_LIMITER           *: string = "limiter"
    CLAP_PLUGIN_FEATURE_FLANGER           *: string = "flanger"
    CLAP_PLUGIN_FEATURE_CHORUS            *: string = "chorus"
    CLAP_PLUGIN_FEATURE_DELAY             *: string = "delay"
    CLAP_PLUGIN_FEATURE_REVERB            *: string = "reverb"
    CLAP_PLUGIN_FEATURE_TREMOLO           *: string = "tremolo"
    CLAP_PLUGIN_FEATURE_GLITCH            *: string = "glitch"
    CLAP_PLUGIN_FEATURE_UTILITY           *: string = "utility"
    CLAP_PLUGIN_FEATURE_PITCH_CORRECTION  *: string = "pitch-correction"
    CLAP_PLUGIN_FEATURE_RESTORATION       *: string = "restoration"
    CLAP_PLUGIN_FEATURE_MULTI_EFFECTS     *: string = "multi-effects"
    CLAP_PLUGIN_FEATURE_MIXING            *: string = "mixing"
    CLAP_PLUGIN_FEATURE_MASTERING         *: string = "mastering"
    CLAP_PLUGIN_FEATURE_MONO              *: string = "mono"
    CLAP_PLUGIN_FEATURE_STEREO            *: string = "stereo"
    CLAP_PLUGIN_FEATURE_SURROUND          *: string = "surround"
    CLAP_PLUGIN_FEATURE_AMBISONIC         *: string = "ambisonic"


proc char_arr_name*(s: string): array[CLAP_NAME_SIZE, char] =
    if s.len == 0:
        result[0] = '\0'
    else:
        let smaller = min(CLAP_NAME_SIZE, s.len)
        for i in 0 ..< smaller:
            result[i] = s[i]
        result[smaller] = '\0'

proc char_arr_path*(s: string): array[CLAP_PATH_SIZE, char] =
    if s.len == 0:
        result[0] = '\0'
    else:
        let smaller = min(CLAP_PATH_SIZE, s.len)
        for i in 0 ..< smaller:
            result[i] = s[i]
        result[smaller] = '\0'
