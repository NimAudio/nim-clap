import shared, process, events

const CLAP_EXT_PARAMS *: cstring = "clap.params"

type
    ClapParamInfoFlag* {.size:sizeof(uint32).} = enum
            # Is this param stepped? (integer values only)
            # if so the double value is converted to integer using a cast (equivalent to trunc).
        cpiIS_STEPPED,

        cpiIS_PERIODIC, # Useful for periodic parameters like a phase
        cpiIS_HIDDEN,   # The parameter should not be shown to the user, because it is currently not used. It is not necessary to process automation for this parameter.
        cpiIS_READONLY, # The parameter can't be changed by the host.

            # This parameter is used to merge the plugin and host bypass button.
            # It implies that the parameter is stepped. min: 0 -> bypass off, max: 1 -> bypass on
        cpiIS_BYPASS,

            # When set: automation can be recorded, automation can be played back
            # The host can send live user changes for this parameter regardless of this flag.
            # If this parameter affects the internal processing structure of the plugin, ie: max delay, fft, size, ...
            # and the plugins needs to re-allocate its working buffers, then it should call
            # host->request_restart(), and perform the change once the plugin is re-activated.
        cpiIS_AUTOMATABLE,

        cpiIS_AUTOMATABLE_PER_NOTE_ID, # Does this parameter support per note automations?
        cpiIS_AUTOMATABLE_PER_KEY,     # Does this parameter support per key automations?
        cpiIS_AUTOMATABLE_PER_CHANNEL, # Does this parameter support per channel automations?
        cpiIS_AUTOMATABLE_PER_PORT,    # Does this parameter support per port automations?
        cpiIS_MODULATABLE,             # Does this parameter support the modulation signal?
        cpiIS_MODULATABLE_PER_NOTE_ID, # Does this parameter support per note modulations?
        cpiIS_MODULATABLE_PER_KEY,     # Does this parameter support per key modulations?
        cpiIS_MODULATABLE_PER_CHANNEL, # Does this parameter support per channel modulations?
        cpiIS_MODULATABLE_PER_PORT,    # Does this parameter support per port modulations?

            # Any change to this parameter will affect the plugin output and requires to be done via process() if the plugin is active.
            # A simple example would be a DC Offset, changing it will change the output signal and must be processed.
        cpiREQUIRES_PROCESS,

            # This parameter represents an enumerated value.
            # If you set this flag, then you must set CLAP_PARAM_IS_STEPPED too.
            # All values from min to max must not have a blank value_to_text().
        cpiIS_ENUM
    ClapParamInfoFlags* = distinct uint32

converter conv_clap_param_info_flags*(flags: set[ClapParamInfoFlag]): ClapParamInfoFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (2'u32 shl ord(f))
    return ClapParamInfoFlags(res)

type
    ClapParamRescanFlag* {.size:sizeof(uint32).} = enum
            # The parameter values did change, eg. after loading a preset.
            # The host will scan all the parameters value.
            # The host will not record those changes as automation points.
            # New values takes effect immediately.
        cprVALUES,

            # The value to text conversion changed, and the text needs to be rendered again.
        cprTEXT,

            # The parameter info did change, use this flag for:
            # - name change
            # - module change
            # - is_periodic (flag)
            # - is_hidden (flag)
            # New info takes effect immediately.
        cprINFO,

            # Invalidates everything the host knows about parameters.
            # It can only be used while the plugin is deactivated.
            # If the plugin is activated use clap_host->restart() and delay any change until the host calls
            # clap_plugin->deactivate().
            #
            # You must use this flag if:
            # - some parameters were added or removed.
            # - some parameters had critical changes:
            #   - is_per_note (flag)
            #   - is_per_key (flag)
            #   - is_per_channel (flag)
            #   - is_per_port (flag)
            #   - is_readonly (flag)
            #   - is_bypass (flag)
            #   - is_stepped (flag)
            #   - is_modulatable (flag)
            #   - min_value
            #   - max_value
            #   - cookie
        cprALL
    ClapParamRescanFlags* = distinct uint32

converter conv_clap_param_rescan_flags*(flags: set[ClapParamRescanFlag]): ClapParamRescanFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (2'u32 shl ord(f))
    return ClapParamRescanFlags(res)

type
    ClapParamClearFlag* {.size:sizeof(uint32).} = enum
        cpcALL,         # Clears all possible references to a parameter
        cpcAUTOMATIONS, # Clears all automations to a parameter
        cpcMODULATIONS  # Clears all modulations to a parameter
    ClapParamClearFlags* = distinct uint32

converter conv_clap_param_clear_flags*(flags: set[ClapParamClearFlag]): ClapParamClearFlags =
    var res: uint32 = 0
    for f in flags:
        res = res or (2'u32 shl ord(f))
    return ClapParamClearFlags(res)

type
    ClapParamInfo* = ClapParamInfoT
    ClapParamInfoT* = object
        id            *: ClapID # Stable parameter identifier, it must never change.
        flags         *: ClapParamInfoFlags

            # This value is optional and set by the plugin.
            # Its purpose is to provide fast access to the plugin parameter object by caching its pointer.
            # For instance:
            #
            # in clap_plugin_params.get_info():
            #    Parameter *p = findParameter(param_id);
            #    param_info->cookie = p;
            #
            # later, in clap_plugin.process():
            #
            #    Parameter *p = (Parameter *)event->cookie;
            #    if (!p) [[unlikely]]
            #       p = findParameter(event->param_id);
            #
            # where findParameter() is a function the plugin implements to map parameter ids to internal
            # objects.
            #
            # Important:
            #  - The cookie is invalidated by a call to clap_host_params->rescan(CLAP_PARAM_RESCAN_ALL) or
            #    when the plugin is destroyed.
            #  - The host will either provide the cookie as issued or nullptr in events addressing
            #    parameters.
            #  - The plugin must gracefully handle the case of a cookie which is nullptr.
            #  - Many plugins will process the parameter events more quickly if the host can provide the
            #    cookie in a faster time than a hashmap lookup per param per event.
        cookie        *: pointer

            # The display name. eg: "Volume". This does not need to be unique.
            # Do not include the module text in this.
            # The host should concatenate/format the module + name in the case where showing the name alone would be too vague.
        name          *: array[CLAP_NAME_SIZE, char]

            # The module path containing the param, eg: "Oscillators/Wavetable 1".
            # '/' will be used as a separator to show a tree-like structure.
        module        *: array[CLAP_NAME_SIZE, char]

        min_value     *: float64 # Minimum plain value
        max_value     *: float64 # Maximum plain value
        default_value *: float64 # Default plain value

    ClapPluginParams* = ClapPluginParamsT
    ClapPluginParamsT* = object
            # Returns the number of parameters. [main-thread]
        count         *: proc (plugin: ptr ClapPlugin): uint32 {.cdecl.}

            # Copies the parameter's info to param_info.
            # Returns true on success. [main-thread]
        get_info      *: proc (plugin:   ptr ClapPlugin,
                            param_index: uint32,
                            param_info:  var ptr ClapParamInfo): bool {.cdecl.}

            # Writes the parameter's current value to out_value.
            # Returns true on success. [main-thread]
        get_value     *: proc (plugin: ptr ClapPlugin,
                            param_id:  ClapID,
                            out_value: ptr float64): bool {.cdecl.}

            # Fills out_buffer with a null-terminated UTF-8 string that represents
            # the parameter at the given 'value' argument. eg: "2.3 kHz".
            # The host should always use this to format parameter
            # values before displaying it to the user.
            # Returns true on success. [main-thread]
        value_to_text *: proc (plugin:               ptr ClapPlugin,
                                param_id:            ClapID,
                                value:               float64,
                                out_buffer:          var cstring,
                                out_buffer_capacity: uint32): bool {.cdecl.}

            # Converts the null-terminated UTF-8 param_value_text into a double and writes it to out_value.
            # The host can use this to convert user input into a parameter value.
            # Returns true on success. [main-thread]
        text_to_value *: proc (plugin   : ptr ClapPlugin,
                                id      : ClapID,
                                display : cstring,
                                value   : var ptr float64): bool {.cdecl.}

            # Flushes a set of parameter changes.
            # This method must not be called concurrently to clap_plugin->process().
            # Note: if the plugin is processing, then the process() call will already achieve the
            # parameter update (bi-directional), so a call to flush isn't required, also be aware
            # that the plugin may use the sample offset in process(), while this information would be
            # lost within flush().
            # [active ? audio-thread : main-thread]
        flush         *: proc (plugin:      ptr ClapPlugin,
                                in_events:  ptr ClapInputEvents,
                                out_events: ptr ClapOutputEvents): void {.cdecl.}

    ClapHostParams* = ClapHostParamsT
    ClapHostParamsT* = object
            # Rescan the full list of parameters according to the flags. [main-thread]
        rescan        *: proc (host: ptr ClapHost,
                                flags: ClapParamRescanFlags): void {.cdecl.}

            # Clears references to a parameter. [main-thread]
        clear         *: proc (host: ptr ClapHost,
                                param_id: ClapID,
                                flags: ClapParamRescanFlags): void {.cdecl.}

            # Request a parameter flush.
            # The host will then schedule a call to either:
            # - clap_plugin.process()
            # - clap_plugin_params.flush()
            #
            # This function is always safe to use and should not be called from an [audio-thread]
            # as the plugin would already be within process() or flush().
            # [thread-safe,!audio-thread]
        request_flush *: proc (host: ptr ClapHost): void {.cdecl.}
