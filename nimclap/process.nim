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
        desc             *: ptr ClapPluginDescriptor
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
        process          *: proc (plugin: ptr ClapPlugin, process: ptr ClapProcess): ClapProcessStatus {.cdecl.}

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
