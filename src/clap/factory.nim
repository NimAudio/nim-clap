import plugin

const CLAP_PLUGIN_FACTORY_ID *: cstring = "clap.plugin-factory"

type
    ClapPluginFactory* = ClapPluginFactoryT
    ClapPluginFactoryT* = object
        get_plugin_count      *: proc (factory: ptr ClapPluginFactory): uint32 {.cdecl.}
        get_plugin_descriptor *: proc (factory: ptr ClapPluginFactory,
                                        index:  uint32): ptr ClapPluginDescriptor {.cdecl.}
        create_plugin         *: proc (factory:    ptr ClapPluginFactory,
                                        host:      ptr ClapHost,
                                        plugin_id: cstring): ptr ClapPlugin {.cdecl.}
