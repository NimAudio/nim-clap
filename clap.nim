import futhark

# plugin features
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

# version
const
    CLAP_VERSION_MAJOR    *: uint32 = 1
    CLAP_VERSION_MINOR    *: uint32 = 2
    CLAP_VERSION_REVISION *: uint32 = 0

const
    CLAP_NAME_SIZE* = 256
    CLAP_PATH_SIZE* = 1024

type ClapID* = distinct uint32
const CLAP_INVALID_ID* = high(ClapID)

# ports
const
    CLAP_PORT_MONO   *: cstring = "mono"
    CLAP_PORT_STEREO *: cstring = "stereo"

# extensions
const
    CLAP_EXT_AUDIO_PORTS  *: cstring = "clap.audio-ports"
    CLAP_EXT_NOTE_PORTS   *: cstring = "clap.note-ports"
    CLAP_EXT_LOG          *: cstring = "clap.log"
    CLAP_EXT_THREAD_CHECK *: cstring = "clap.thread-check"
    CLAP_EXT_LATENCY      *: cstring = "clap.latency"
    CLAP_EXT_STATE        *: cstring = "clap.state"

const
    CLAP_CORE_EVENT_SPACE_ID: uint16 = 0

type
    ClapAudioBuffer* = ClapAudioBufferT
    ClapAudioBufferT* = object
        data32        *: ptr UncheckedArray[ptr UncheckedArray[float32]]
        data64        *: ptr UncheckedArray[ptr UncheckedArray[float64]]
        channel_count *: uint32
        latency       *: uint32
        constant_mask *: uint64

    ClapProcessStatus* {.size:sizeof(int32).} = enum
        cpsERROR                 = 0,
        cpsCONTINUE              = 1,
        cpsCONTINUE_IF_NOT_QUIET = 2,
        cpsTAIL                  = 3,
        cpsSLEEP                 = 4

    ClapProcess* = ClapProcessT
    ClapProcessT* = object
        steady_time         *: int64
        frames_count        *: uint32
        # transport         *: ptr UncheckedArray[ClapEventTransport]
        transport           *: pointer # just don't use it until i define it
        audio_inputs        *: ptr UncheckedArray[ClapAudioBuffer]
        audio_outputs       *: ptr UncheckedArray[ClapAudioBuffer]
        audio_inputs_count  *: uint32
        audio_outputs_count *: uint32
        in_events           *: ptr ClapInputEvents
        out_events          *: ptr ClapOutputEvents

    ClapVersion* = ClapVersionT
    ClapVersionT* = object
        major    *: uint32
        minor    *: uint32
        revision *: uint32

    ClapPluginDescriptor* = ClapPluginDescriptorT
    ClapPluginDescriptorT* = object
        clap_version *: ClapVersion
        id           *: cstring
        name         *: cstring
        vendor       *: cstring
        url          *: cstring
        manual_url   *: cstring
        support_url  *: cstring
        version      *: cstring
        description  *: cstring
        # features   *: ptr UncheckedArray[cstring]
        features     *: cstringArray

    ClapPlugin* = ClapPluginT
    ClapPluginT* = object
        desc             *: ClapPluginDescriptor
        plugin_data      *: pointer

        # Must be called after creating the plugin.
        # If init returns false, the host must destroy the plugin instance.
        # If init returns true, then the plugin is initialized and in the deactivated state.
        # Unlike in `plugin-factory::create_plugin`, in init you have complete access to the host and host extensions,
        # so clap related setup activities should be done here rather than in create_plugin.
        #[main-thread]#
        init             *: proc (plugin: ptr ClapPlugin): bool {.cdecl.}
        # Free the plugin and its resources. It is required to deactivate the plugin prior to this call.
        #[main-thread & !active]#
        destroy          *: proc (plugin: ptr ClapPlugin): void {.cdecl.}

        # Activate and deactivate the plugin.
        # In this call the plugin may allocate memory and prepare everything needed for the process
        # call. The process's sample rate will be constant and process's frame count will included in
        # the [min, max] range, which is bounded by [1, INT32_MAX].
        # Once activated the latency and port configuration must remain constant, until deactivation.
        # Returns true on success.
        #[main-thread & !active]#
        activate         *: proc (plugin: ptr ClapPlugin, sample_rate: float64, min_frames_count: uint32, max_frames_count: uint32): bool {.cdecl.}
        #[main-thread & active]#
        deactivate       *: proc (plugin: ptr ClapPlugin): void {.cdecl.}

        # Call start processing before processing.
        # Returns true on success.
        # [audio-thread & active & !processing]
        start_processing *: proc (plugin: ptr ClapPlugin): bool {.cdecl.}
        # Call stop processing before sending the plugin to sleep.
        # [audio-thread & active & processing]
        stop_processing  *: proc (plugin: ptr ClapPlugin): void {.cdecl.}

        # Clears all buffers, performs a full reset of the processing state
        # (filters, oscillators, envelopes, lfo, ...) and kills all voices.
        # The parameter's value remain unchanged. clap_process.steady_time may jump backward.
        # [audio-thread & active]
        reset            *: proc (plugin: ptr ClapPlugin): void {.cdecl.}

        # process audio, events, ...
        # All the pointers coming from clap_process_t and its nested attributes are valid until process() returns.
        # [audio-thread & active & processing]
        process          *: proc (plugin: ptr ClapPlugin, process: ClapProcess): ClapProcessStatus {.cdecl.}

        # Query an extension. The returned pointer is owned by the plugin.
        # It is forbidden to call it before plugin->init(). You can call it within plugin->init() call, and after.
        # [thread-safe]
        get_extension    *: proc (plugin: ptr ClapPlugin, id: cstring): pointer {.cdecl.}

        # Called by the host on the main thread in response to a previous call to: host->request_callback(host);
        # [main-thread]
        on_main_thread   *: proc (plugin: ptr ClapPlugin): void {.cdecl.}

    ClapHost* = ClapHostT
    ClapHostT* = object
        clap_version     *: ClapVersion
        host_data        *: pointer
        name             *: cstring
        vendor           *: cstring
        url              *: cstring
        version          *: cstring
        get_extension    *: proc (host: ptr ClapHost, extension_id: cstring): pointer {.cdecl.} # Query an extension.
        request_restart  *: proc (host: ptr ClapHost): void {.cdecl.} # Request the host to deactivate and then reactivate the plugin.
        request_process  *: proc (host: ptr ClapHost): void {.cdecl.} # Request the host to activate and start processing the plugin.
        request_callback *: proc (host: ptr ClapHost): void {.cdecl.} # Request the host to schedule a call to plugin->on_main_thread(plugin) on the main thread.

    ClapPluginLatency* = ClapPluginLatencyT
    ClapPluginLatencyT* = object
        # Returns the plugin latency in samples.
        # [main-thread & active]
        get*: proc (plugin: ptr ClapPlugin): uint32 {.cdecl.}

    ClapHostLatency* = ClapHostLatencyT
    ClapHostLatencyT* = object
        # Tell the host that the latency changed.
        # The latency is only allowed to change if the plugin is deactivated.
        # If the plugin is activated, call host->request_restart()
        # [main-thread]
        changed*: proc (plugin: ptr ClapHost): void {.cdecl.}

    ClapLogSeverity* {.size:sizeof(int32).} = enum
        clsDEBUG              = 0,
        clsINFO               = 1,
        clsWARNING            = 2,
        clsERROR              = 3,
        clsFATAL              = 4,
        clsHOST_MISBEHAVING   = 5,
        clsPLUGIN_MISBEHAVING = 6

    ClapHostLog* = ClapHostLogT
    ClapHostLogT* = object
        # Log a message through the host.
        log*: proc (host: ptr ClapHost, severity: ClapLogSeverity, msg: cstring): void {.cdecl.}

    ClapHostThreadCheck* = ClapHostThreadCheckT
    ClapHostThreadCheckT* = object
        is_main_thread  *: proc (host: ptr ClapHost): bool {.cdecl.}
        is_audio_thread *: proc (host: ptr ClapHost): bool {.cdecl.}

    ClapIStream* = ClapIStreamT
    ClapIStreamT* = object
        ctx*: pointer
        read*: proc (stream: ptr ClapIStream, buffer: pointer, size: uint64): int64 {.cdecl.}

    ClapOStream* = ClapOStreamT
    ClapOStreamT* = object
        ctx*: pointer
        write*: proc (stream: ptr ClapOStream, buffer: pointer, size: uint64): int64 {.cdecl.}

    ClapPluginState* = ClapPluginStateT
    ClapPluginStateT* = object
        save*: proc (plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.}
        load*: proc (plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.}

    ClapHostState* = ClapHostStateT
    ClapHostStateT* = object
        mark_dirty*: proc (host: ptr ClapHost): void {.cdecl.}

    ClapAudioPortFlag* {.size:sizeof(uint32).} = enum
        capfIS_MAIN,
        capfSUPPORTS_64BITS,
        capfPREFERS_64BITS,
        capfREQUIRES_COMMON_SAMPLE_SIZE
    ClapAudioPortFlags* = set[ClapAudioPortFlag]

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

    ClapAudioPortRescanFlag* {.size:sizeof(uint32).} = enum
        caprNAMES,
        caprFLAGS,
        caprCHANNEL_COUNT,
        caprPORT_TYPE,
        caprIN_PLACE_PAIR,
        caprLIST
    ClapAudioPortRescanFlags* = set[ClapAudioPortRescanFlag]

    ClapHostAudioPorts* = ClapHostAudioPortsT
    ClapHostAudioPortsT* = object
        is_rescan_flag_supported *: proc (host: ptr ClapHost, flags: ClapAudioPortRescanFlags): bool {.cdecl.}
        rescan                   *: proc (host: ptr ClapHost, flags: ClapAudioPortRescanFlags): void {.cdecl.}

    ClapNoteDialectFlag* {.size:sizeof(uint32).} = enum
        cndCLAP,
        cndMIDI,
        cndMIDI_MPE,
        cndMIDI2
    ClapNoteDialectFlags* = set[ClapNoteDialectFlag]

    ClapNotePortInfo* = ClapNotePortInfoT
    ClapNotePortInfoT* = object
        id                 *: ClapID
        supported_dialects *: ClapNoteDialectFlags
        preferred_dialect  *: ClapNoteDialectFlags
        name               *: array[CLAP_NAME_SIZE, char]

    ClapPluginNotePorts* = ClapPluginNotePortsT
    ClapPluginNotePortsT* = object
        count *: proc (plugin: ptr ClapPlugin, is_input: bool): uint32 {.cdecl.}
        get   *: proc (plugin: ptr ClapPlugin,
                        index: uint32,
                        is_input: bool,
                        info: ptr ClapNotePortInfo): bool {.cdecl.}

    ClapNotePortRescanFlag* {.size:sizeof(uint32).} = enum
        cnprALL,
        cnprNAMES
    ClapNotePortRescanFlags* = set[ClapNotePortRescanFlag]

    ClapHostNotePorts* = ClapHostNotePortsT
    ClapHostNotePortsT* = object
        supported_dialects *: proc (host: ptr ClapHost): uint32 {.cdecl.}
        rescan             *: proc (host: ptr ClapHost, flags: uint32): void {.cdecl.}

    ClapEventHeader* = ClapEventHeaderT
    ClapEventHeaderT* = object
        size       *: uint32        # event size including this header, eg: sizeof (clap_event_note)
        time       *: uint32        # sample offset within the buffer for this event
        space_id   *: uint32        # event space, see clap_host_event_registry
        event_type *: ClapEventType # event type, originally named `type`
        flags      *: uint32        # see clap_event_flags

    ClapEventFlag* {.size:sizeof(uint32).} = enum
        ceIS_LIVE,
        ceDONT_RECORD
    ClapEventFlags* = set[ClapEventFlag]

    ClapEventType* {.size:sizeof(uint32).} = enum
        cetNOTE_ON             = 0,  #
        cetNOTE_OFF            = 1,  #
        cetNOTE_CHOKE          = 2,  #
        cetNOTE_END            = 3,  #
        cetNOTE_EXPRESSION     = 4,  # Represents a note expression; Uses clap_event_note_expression.
        cetPARAM_VALUE         = 5,  # PARAM_VALUE sets the parameter's value; uses clap_event_param_value.
        cetPARAM_MOD           = 6,  # PARAM_MOD sets the parameter's modulation amount; uses clap_event_param_mod.
        cetPARAM_GESTURE_BEGIN = 7,  # Indicates that the user started or finished adjusting a knob.
        cetPARAM_GESTURE_END   = 8,  #
        cetTRANSPORT           = 9,  # update the transport info; clap_event_transport
        cetMIDI                = 10, # raw midi event; clap_event_midi
        cetMIDI_SYSEX          = 11, # raw midi sysex event; clap_event_midi_sysex
        cetMIDI2               = 12  # raw midi 2 event; clap_event_midi2

    # wildcard, -1, means apply to all notes matching the other parts
    ClapEventNote* = ClapEventNoteT
    ClapEventNoteT* = object
        header     *: ClapEventHeader
        note_id    *: int32   # host provided note id >= 0, or -1 if unspecified or wildcard
        port_index *: int16   # port index from ext/note-ports; -1 for wildcard
        channel    *: int16   # 0..15, same as MIDI1 Channel Number, -1 for wildcard
        key        *: int16   # 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
        velocity   *: float64 # 0..1

    ClapNoteExpressionType* {.size:sizeof(int32).} = enum
        cneVOLUME     = 0, # with 0 < x <= 4, plain = 20 * log(x)
        cnePAN        = 1, # pan, 0 left, 0.5 center, 1 right

        # Relative tuning in semitones, from -120 to +120.
        # Semitones are in equal temperament and are doubles;
        # the resulting note would be retuned by `100 * evt->value` cents.
        cneTUNING     = 2,

        cneVIBRATO    = 3, # 0..1
        cneEXPRESSION = 4, # 0..1
        cneBRIGHTNESS = 5, # 0..1
        cnePRESSURE   = 6, # 0..1

    ClapNoteExpression* = distinct int32

    # wildcard, -1, means apply to all notes matching the other parts
    ClapEventNoteExpression* = ClapEventNoteExpressionT
    ClapEventNoteExpressionT* = object
        header     *: ClapEventHeader
        note_id    *: int32   # host provided note id >= 0, or -1 if unspecified or wildcard
        port_index *: int16   # port index from ext/note-ports; -1 for wildcard
        channel    *: int16   # 0..15, same as MIDI1 Channel Number, -1 for wildcard
        key        *: int16   # 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
        value      *: float64 # 0..1

    # wildcard, -1, means apply to all notes matching the other parts
    ClapEventParamMod* = ClapEventParamModT
    ClapEventParamModT* = ClapEventParamValueT
    ClapEventParamValue* = ClapEventParamValueT  # combines identical _value and _mod types,
    ClapEventParamValueT* = object               # which only differ in the name of one variable
        header     *: ClapEventHeader
        param_id   *: ClapID
        cookie     *: pointer
        note_id    *: int32   # host provided note id >= 0, or -1 if unspecified or wildcard
        port_index *: int16   # port index from ext/note-ports; -1 for wildcard
        channel    *: int16   # 0..15, same as MIDI1 Channel Number, -1 for wildcard
        key        *: int16   # 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
        val_amt    *: float64 # 0..1

    ClapEventParamGesture* = ClapEventParamGestureT
    ClapEventParamGestureT* = object
        header   *: ClapEventHeader
        param_id *: ClapID

    # ClapTransportFlag* {.size:sizeof(uint32).} = enum
    #     ctHAS_TEMPO,
    #     ctHAS_BEATS_TIMELINE,
    #     ctHAS_SECONDS_TIMELINE,
    #     ctHAS_TIME_SIGNATURE,
    #     ctIS_PLAYING,
    #     ctIS_RECORDING,
    #     ctIS_LOOP_ACTIVE,
    #     ctIS_WITHIN_PRE_ROLL
    # ClapTransportFlags* = set[ClapTransportFlag]
    # oops i forgot i wasn't implementing transport yet

    ClapEventMidi* = ClapEventMidiT
    ClapEventMidiT* = object
        header     *: ClapEventHeader
        port_index *: uint16
        data       *: array[3, uint8]

    ClapEventMidiSysex* = ClapEventMidiSysexT
    ClapEventMidiSysexT* = object
        header     *: ClapEventHeader
        port_index *: uint16
        buffer     *: ptr UncheckedArray[uint8]
        size       *: uint32

    ClapEventMidi2* = ClapEventMidi2T
    ClapEventMidi2T* = object
        header     *: ClapEventHeader
        port_index *: uint16
        data       *: array[4, uint32]

    ClapEventUnion* {.union.} = object
        # contains header in all
        kindNote         *: ClapEventNote
        kindNoteExpr     *: ClapEventNoteExpression
        kindParamValMod  *: ClapEventParamValue
        kindParamGesture *: ClapEventParamGesture
        # transport missing
        kindMidi         *: ClapEventMidi
        kindMidiSysex    *: ClapEventMidiSysex
        kindMidi2        *: ClapEventMidi2

    ClapInputEvents* = ClapInputEventsT
    ClapInputEventsT* = object
        ctx *: pointer
        size *: proc (list: ptr ClapInputEvents): uint32
        get *: proc (list: ptr ClapInputEvents, index: uint32): ptr ClapEventUnion

    ClapOutputEvents* = ClapOutputEventsT
    ClapOutputEventsT* = object
        ctx *: pointer
        try_push *: proc (list: ptr ClapOutputEvents, event: ptr ClapEventUnion): bool

type
    MyPlug* = object
        plugin            *: ptr ClapPlugin
        host              *: ptr ClapHost
        host_latency      *: ptr ClapHostLatency
        host_log          *: ptr ClapHostLog
        host_thread_check *: ptr ClapHostThreadCheck
        host_state        *: ptr ClapHostState
        latency           *: uint32

# Tell futhark where to find the C libraries you will compile with, and what
# header files you wish to import.
importc:
    path "../clap-main/include/clap"
    "clap.h"

