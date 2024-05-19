import events


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
