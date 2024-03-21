import shared

type
    ClapEventFlag* {.size:sizeof(uint32).} = enum
        ceIS_LIVE,
        ceDONT_RECORD
    ClapEventFlags* = distinct uint32

converter conv_clap_event_flags*(flags: set[ClapEventFlag]): ClapEventFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (2'u32 shl ord(f))
    return ClapEventFlags(res)

type
    ClapEventHeader* = ClapEventHeaderT
    ClapEventHeaderT* = object
        size       *: uint32         # event size including this header, eg: sizeof (clap_event_note)
        time       *: uint32         # sample offset within the buffer for this event
        space_id   *: uint32         # event space, see clap_host_event_registry
        event_type *: ClapEventType  # event type, originally named `type`
        flags      *: ClapEventFlags

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
        size *: proc (list: ptr ClapInputEvents): uint32 {.cdecl.}
        get *: proc (list: ptr ClapInputEvents, index: uint32): ptr ClapEventUnion {.cdecl.}

    ClapOutputEvents* = ClapOutputEventsT
    ClapOutputEventsT* = object
        ctx *: pointer
        try_push *: proc (list: ptr ClapOutputEvents, event: ptr ClapEventUnion): bool {.cdecl.}