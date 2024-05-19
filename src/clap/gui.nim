import shared, process # process contains ClapPlugin, which should probably be moved to its own file

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

    ClapWindow* = ClapWindowT
    ClapWindowT* = object
        api    *: cstring
        handle *: ClapWindowHandle

    ClapGUIResizeHints* = ClapGUIResizeHintsT
    ClapGUIResizeHintsT* = object
        can_resize_horizontally *: bool
        can_resize_vertically   *: bool
        preserve_aspect_ratio   *: bool
        aspect_ratio_width      *: uint32
        aspect_ratio_height     *: uint32

    ClapPluginGUI* = ClapPluginGUIT
    ClapPluginGUIT* = object
        is_api_supported  *: proc (plugin: ptr ClapPlugin, api:     cstring, is_floating: bool) : bool {.cdecl.} # [main-thread]
        get_preferred_api *: proc (plugin: ptr ClapPlugin, api: ptr cstring, is_floating: bool) : bool {.cdecl.} # [main-thread]
        create            *: proc (plugin: ptr ClapPlugin, api:     cstring, is_floating: bool) : bool {.cdecl.} # [main-thread]
        destroy           *: proc (plugin: ptr ClapPlugin)                                      : void {.cdecl.} # [main-thread]
        set_scale         *: proc (plugin: ptr ClapPlugin, scale: float64)                      : bool {.cdecl.} # [main-thread]
        get_size          *: proc (plugin: ptr ClapPlugin, width, height: ptr uint32)           : bool {.cdecl.} # [main-thread]
        can_resize        *: proc (plugin: ptr ClapPlugin)                                      : bool {.cdecl.} # [main-thread & !floating]
        get_resize_hints  *: proc (plugin: ptr ClapPlugin, hints: ptr ClapGUIResizeHints)       : bool {.cdecl.} # [main-thread & !floating]
        adjust_size       *: proc (plugin: ptr ClapPlugin, width, height: ptr uint32)           : bool {.cdecl.} # [main-thread & !floating]
        set_size          *: proc (plugin: ptr ClapPlugin, width, height:     uint32)           : bool {.cdecl.} # [main-thread & !floating]
        set_parent        *: proc (plugin: ptr ClapPlugin, window: ptr ClapWindow)              : bool {.cdecl.} # [main-thread & !floating]
        set_transient     *: proc (plugin: ptr ClapPlugin, window: ptr ClapWindow)              : bool {.cdecl.} # [main-thread & floating]
        suggest_title     *: proc (plugin: ptr ClapPlugin, title: cstring)                      : void {.cdecl.} # [main-thread & floating]
        show              *: proc (plugin: ptr ClapPlugin)                                      : bool {.cdecl.} # [main-thread]
        hide              *: proc (plugin: ptr ClapPlugin)                                      : bool {.cdecl.} # [main-thread]

    ClapHostGUI* = ClapHostGUIT
    ClapHostGUIT* = object
        resize_hints_changed *: proc (host: ptr ClapHost)                        : void {.cdecl.} # [thread-safe & !floating]
        request_resize       *: proc (host: ptr ClapHost, width, height: uint32) : bool {.cdecl.} # [thread-safe & !floating]
        request_show         *: proc (host: ptr ClapHost)                        : bool {.cdecl.} # [thread-safe]
        request_hide         *: proc (host: ptr ClapHost)                        : bool {.cdecl.} # [thread-safe]
        closed               *: proc (host: ptr ClapHost, was_destroyed: bool)   : void {.cdecl.} # [thread-safe]