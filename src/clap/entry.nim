import shared, factory

type
    ClapPluginEntry* = object
        clap_version *: ClapVersion
        init         *: proc (plugin_path: cstring): bool {.cdecl.}
        deinit       *: proc (): void {.cdecl.}
        get_factory  *: proc (factory_id: cstring): ptr ClapPluginFactory {.cdecl.}