import plugin, shared

const
    CLAP_EXT_TIMER_SUPPORT *: cstring = "clap.timer-support"

type
    ClapPluginTimer* = object
        ## Plugin-implemented timer procs
        ##
        ## **on_timer** *main-thread*
        ## Called every `period_ms`
        ##
        on_timer *: proc (plugin: ptr ClapPlugin, timer_id: ClapID): void {.cdecl.}

    ClapHostTimer* = object
        ## Host-implemented timer procs
        ##
        ## **register_timer** *main-thread*
        ## Registers a periodic timer.
        ## The host may adjust the period if it is under a certain threshold.
        ## 30 Hz should be allowed.
        ## Returns true on success.
        ##
        ## **unregister_timer** *main-thread*
        ## Returns true on success.
        ##
        register_timer   *: proc (host: ptr ClapHost, period_ms: uint32, timer_id: ptr ClapID): bool {.cdecl.}
        unregister_timer *: proc (host: ptr ClapHost,                    timer_id:     ClapID): bool {.cdecl.}
