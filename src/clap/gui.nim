import plugin

const
    CLAP_EXT_GUI *: cstring = "clap.gui"

    # uses physical size
    # embed using https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent
    CLAP_WINDOW_API_WIN32 *: cstring = "win32"

    # uses logical size, don't call clap_plugin_gui->set_scale()
    CLAP_WINDOW_API_COCOA *: cstring = "cocoa"

    # uses physical size
    # embed using https://specifications.freedesktop.org/xembed-spec/xembed-spec-latest.html
    CLAP_WINDOW_API_X11 *: cstring = "x11"

    # uses physical size
    # embed is currently not supported, use floating windows
    CLAP_WINDOW_API_WAYLAND *: cstring = "wayland"

type
    ClapHWND * = pointer
    ClapNSView * = pointer
    ClapXWND * = uint64

    ClapWindowHandle* {.union.} = object
        cocoa *: ClapNSView
        x11   *: ClapXWND # wayland?
        win32 *: ClapHWND
        other *: pointer

    # ClapWindow* = ClapWindowT
    # ClapWindowT* = object
    ClapWindow* = object
        api    *: cstring
        handle *: ClapWindowHandle

    # ClapGUIResizeHints* = ClapGUIResizeHintsT
    # ClapGUIResizeHintsT* = object
    ClapGUIResizeHints* = object
        can_resize_horizontally *: bool
        can_resize_vertically   *: bool
        preserve_aspect_ratio   *: bool
        aspect_ratio_width      *: uint32
        aspect_ratio_height     *: uint32

    # ClapPluginGUI* = ClapPluginGUIT
    # ClapPluginGUIT* = object
    ClapPluginGUI* = object
        ## Plugin-implemented ui-related interactions
        ##
        ## **is_api_supported** *main-thread*
        ## Returns true if the requested gui api is supported
        ##
        ## **get_preferred_api** *main-thread*
        ## Returns true if the plugin has a preferred api.
        ## The host has no obligation to honor the plugin preference, this is just a hint.
        ##
        ## The ptr cstring variable should be explicitly assigned as a pointer
        ## to one of the CLAP_WINDOW_API_XYZ constants defined above, not strcopied.
        ##
        ## **create** *main-thread*
        ## Create and allocate all resources necessary for the gui.
        ##
        ## If is_floating is true, then the window will not be managed by the host. The plugin
        ## can set its window to stays above the parent window, see set_transient().
        ## api may be null or blank for floating window.
        ##
        ## If is_floating is false, then the plugin has to embed its window into the parent window, see set_parent().
        ##
        ## After this call, the GUI may not be visible yet; don't forget to call show().
        ##
        ## Returns true if the GUI is successfully created.
        ##
        ## **destroy** *main-thread*
        ## Free all resources associated with the gui.
        ##
        ## **set_scale** *main-thread*
        ## Set the absolute GUI scaling factor, and override any OS info.
        ## Should not be used if the windowing api relies upon logical pixels.
        ##
        ## If the plugin prefers to work out the scaling factor itself
        ## by querying the OS directly, then ignore the call.
        ##
        ## scale = 2 means 200% scaling.
        ##
        ## Returns true if the scaling could be applied
        ## Returns false if the call was ignored, or the scaling could not be applied.
        ##
        ## **get_size** *main-thread*
        ## Get the current size of the plugin UI.
        ## clap_plugin_gui->create() must have been called prior to asking the size.
        ##
        ## Returns true if the plugin could get the size.
        ##
        ## **can_resize** *main-thread & !floating*
        ## Returns true if the window is resizeable (mouse drag).
        ##
        ## **get_resize_hints** *main-thread & !floating*
        ## Returns true if the plugin can provide hints on how to resize the window.
        ##
        ## **adjust_size** *main-thread & !floating*
        ## If the plugin gui is resizable, then the plugin will calculate the closest
        ## usable size which fits in the given size.
        ## This method does not change the size.
        ##
        ## Returns true if the plugin could adjust the given size.
        ##
        ## **set_size** *main-thread & !floating*
        ## Sets the window size.
        ## Returns true if the plugin could resize its window to the given size.
        ##
        ## **set_parent** *main-thread & !floating*
        ## Embeds the plugin window into the given window.
        ## Returns true on success.
        ##
        ## **set_transient** *main-thread & floating*
        ## Set the plugin floating window to stay above the given window.
        ## Returns true on success.
        ##
        ## **suggest_title** *main-thread & floating*
        ## Suggests a window title. Only for floating windows.
        ##
        ## **show** *main-thread*
        ## Show the window.
        ## Returns true on success.
        ##
        ## **hide** *main-thread*
        ## Hide the window, this method does not free the resources, it just hides
        ## the window content. Yet it may be a good idea to stop painting timers.
        ## Returns true on success.
        ##
        is_api_supported  *: proc (plugin: ptr ClapPlugin, api:     cstring, is_floating: bool) : bool {.cdecl.}
        get_preferred_api *: proc (plugin: ptr ClapPlugin, api: ptr cstring, is_floating: bool) : bool {.cdecl.}
        create            *: proc (plugin: ptr ClapPlugin, api:     cstring, is_floating: bool) : bool {.cdecl.}
        destroy           *: proc (plugin: ptr ClapPlugin)                                      : void {.cdecl.}
        set_scale         *: proc (plugin: ptr ClapPlugin, scale: float64)                      : bool {.cdecl.}
        get_size          *: proc (plugin: ptr ClapPlugin, width, height: ptr uint32)           : bool {.cdecl.}
        can_resize        *: proc (plugin: ptr ClapPlugin)                                      : bool {.cdecl.}
        get_resize_hints  *: proc (plugin: ptr ClapPlugin, hints: ptr ClapGUIResizeHints)       : bool {.cdecl.}
        adjust_size       *: proc (plugin: ptr ClapPlugin, width, height: ptr uint32)           : bool {.cdecl.}
        set_size          *: proc (plugin: ptr ClapPlugin, width, height:     uint32)           : bool {.cdecl.}
        set_parent        *: proc (plugin: ptr ClapPlugin, window: ptr ClapWindow)              : bool {.cdecl.}
        set_transient     *: proc (plugin: ptr ClapPlugin, window: ptr ClapWindow)              : bool {.cdecl.}
        suggest_title     *: proc (plugin: ptr ClapPlugin, title: cstring)                      : void {.cdecl.}
        show              *: proc (plugin: ptr ClapPlugin)                                      : bool {.cdecl.}
        hide              *: proc (plugin: ptr ClapPlugin)                                      : bool {.cdecl.}

    # ClapHostGUI* = ClapHostGUIT
    # ClapHostGUIT* = object
    ClapHostGUI* = object
        ## Host-implemented ui-related interactions
        ##
        ## **resize_hints_changed** *thread-safe & !floating*
        ## The host should call get_resize_hints() again.
        ##
        ## **request_resize** *thread-safe & !floating*
        ## Request the host to resize the client area to width, height.
        ## Return true if the new size is accepted, false otherwise.
        ## The host doesn't have to call set_size().
        ## Note: if not called from the main thread, then a return value simply means that the host
        ## acknowledged the request and will process it asynchronously. If the request then can't be
        ## satisfied then the host will call set_size() to revert the operation.
        ##
        ## **request_show** *thread-safe*
        ## Request the host to show the plugin gui.
        ## Return true on success, false otherwise.
        ##
        ## **request_hide** *thread-safe*
        ## Request the host to hide the plugin gui.
        ## Return true on success, false otherwise.
        ##
        ## **closed** *thread-safe*
        ## The floating window has been closed, or the connection to the gui has been lost.
        ## If was_destroyed is true, then the host must call clap_plugin_gui.destroy() to
        ## acknowledge the gui destruction.
        resize_hints_changed *: proc (host: ptr ClapHost)                        : void {.cdecl.}
        request_resize       *: proc (host: ptr ClapHost, width, height: uint32) : bool {.cdecl.}
        request_show         *: proc (host: ptr ClapHost)                        : bool {.cdecl.}
        request_hide         *: proc (host: ptr ClapHost)                        : bool {.cdecl.}
        closed               *: proc (host: ptr ClapHost, was_destroyed: bool)   : void {.cdecl.}
