import plugin

const
    CLAP_EXT_LATENCY *: cstring = "clap.latency"

type
    ClapPluginLatency* = object
        # Returns the plugin latency in samples.
        # [main-thread & active]
        get*: proc (plugin: ptr ClapPlugin): uint32 {.cdecl.}

    ClapHostLatency* = object
        # Tell the host that the latency changed.
        # The latency is only allowed to change if the plugin is deactivated.
        # If the plugin is activated, call host->request_restart()
        # [main-thread]
        changed*: proc (plugin: ptr ClapHost): void {.cdecl.}