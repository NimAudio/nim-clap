import events


type
    ClapAudioBuffer* = object
        ## Audio Buffer
        ## Sample c code for reading a stereo buffer:
        ##
        ## bool isLeftConstant = (buffer->constant_mask & (1 << 0)) != 0;
        ## bool isRightConstant = (buffer->constant_mask & (1 << 1)) != 0;
        ##
        ## for (int i = 0; i < N; ++i) {
        ##    float l = data32[0][isLeftConstant ? 0 : i];
        ##    float r = data32[1][isRightConstant ? 0 : i];
        ## }
        ##
        ## Note: checking the constant mask is optional, and this implies that
        ## the buffer must be filled with the constant value.
        ## Rationale: if a buffer reader doesn't check the constant mask, then it may
        ## process garbage samples and in result, garbage samples may be transmitted
        ## to the audio interface with all the bad consequences it can have.
        ##
        ## The constant mask is a hint.
        ##
        ## **data32**
        ## ptr UncheckedArray, where each index represents a channel,
        ## each containing a ptr UncheckedArray of sample data.
        ## Either data32 or data64 pointer will be set.
        ##
        ## **data64**
        ## ptr UncheckedArray, where each index represents a channel,
        ## each containing a ptr UncheckedArray of sample data.
        ## Either data32 or data64 pointer will be set.
        ##
        ## **channel_count**
        ## Number of channels.
        ##
        ## **latency**
        ## Latency from/to the audio interfaces
        ##
        ## **constant_mask**
        ## Bitmask containing whether each channel in the buffer is constant or an array.
        ## If it is constant, only the first value is set, rather than the normal buffer size.
        ##
        data32        *: ptr UncheckedArray[ptr UncheckedArray[float32]]
        data64        *: ptr UncheckedArray[ptr UncheckedArray[float64]]
        channel_count *: uint32
        latency       *: uint32
        constant_mask *: uint64

    ClapProcessStatus* {.size:sizeof(int32).} = enum
        ## Process Status
        ##
        ## **cpsERROR**
        ## Processing failed. The output buffer must be discarded.
        ##
        ## **cpsCONTINUE**
        ## Processing succeeded, keep processing.
        ##
        ## **cpsCONTINUE_IF_NOT_QUIET**
        ## Processing succeeded, keep processing if the output is not quiet.
        ##
        ## **cpsTAIL**
        ## Rely upon the plugin's tail to determine if the plugin should continue to process. see clap_plugin_tail
        ##
        ## **cpsSLEEP**
        ## Processing succeeded, but no more processing is required, until the next event or variation in audio input.
        ##
        cpsERROR                 = 0,
        cpsCONTINUE              = 1,
        cpsCONTINUE_IF_NOT_QUIET = 2,
        cpsTAIL                  = 3,
        cpsSLEEP                 = 4

    ClapProcess* = object
        ## Host-provided input/output for audio and events
        ##
        ## **steady_time**
        ## A steady sample time counter.
        ## This field can be used to calculate the sleep duration between two process calls.
        ## This value may be specific to this plugin instance and have no relation to what
        ## other plugin instances may receive.
        ##
        ## Set to -1 if not available, otherwise the value must be greater or equal to 0,
        ## and must be increased by at least `frames_count` for the next call to process.
        ##
        ## **frames_count**
        ## Number of frames to process.
        ##
        ## **transport** *required types not implemented*
        ## Time info at sample 0.
        ## If null, then this is a free running host, no transport events will be provided
        ##
        ## **audio_inputs**
        ## **audio_outputs**
        ## **audio_inputs_count**
        ## **audio_outputs_count**
        ## Audio buffers, they must have the same count as specified by clap_plugin_audio_ports->count().
        ## The index maps to clap_plugin_audio_ports->get().
        ## Input buffer and its contents are read-only.
        ##
        ## **in_events**
        ## The input event list can't be modified.
        ## Input read-only event list.
        ## The host will deliver these sorted in sample order.
        ##
        ## **out_events**
        ## Output event list.
        ## The plugin must insert events in sample sorted order when inserting events.
        ##
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
