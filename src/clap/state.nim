import plugin

const
    CLAP_EXT_STATE *: cstring = "clap.state"

## When working with `ClapIStream` and `ClapOStream` objects to load and save
## state, it is important to keep in mind that the host may limit the number of
## bytes that can be read or written at a time. The return values for the
## stream read and write functions indicate how many bytes were actually read
## or written. You need to use a loop to ensure that you read or write the
## entirety of your state. Don't forget to also consider the negative return
## values for the end of file and IO error codes.

type
    ClapIStream* = object
        ## Stream to read data from
        ##
        ## **ctx**
        ## reserved pointer for the stream
        ##
        ## **read** *main-thread?*
        ## returns the number of bytes read; 0 indicates end of file and -1 a read error
        ##
        ctx*: pointer
        read*: proc (stream: ptr ClapIStream, buffer: pointer, size: uint64): int64 {.cdecl.}

    ClapOStream* = object
        ## Stream to write data to
        ##
        ## **ctx**
        ## reserved pointer for the stream
        ##
        ## **write** *main-thread?*
        ## returns the number of bytes written; -1 on write error
        ##
        ctx*: pointer
        write*: proc (stream: ptr ClapOStream, buffer: pointer, size: uint64): int64 {.cdecl.}


## Plugins can implement this extension to save and restore both parameter
## values and non-parameter state. This is used to persist a plugin's state
## between project reloads, when duplicating and copying plugin instances, and
## for host-side preset management.
##
## If you need to know if the save/load operation is meant for duplicating a plugin
## instance, for saving/loading a plugin preset or while saving/loading the project
## then consider implementing CLAP_EXT_STATE_CONTEXT in addition to CLAP_EXT_STATE.

type
    ClapPluginState* = object
        ## Plugin-implemented save/load
        ##
        ## **save** *main-thread*
        ## Saves the plugin state into stream.
        ## Returns true if the state was correctly saved.
        ##
        ## **load** *main-thread*
        ## Loads the plugin state from stream.
        ## Returns true if the state was correctly restored.
        ##
        save*: proc (plugin: ptr ClapPlugin, stream: ptr ClapOStream): bool {.cdecl.}
        load*: proc (plugin: ptr ClapPlugin, stream: ptr ClapIStream): bool {.cdecl.}

    ClapHostState* = object
        ## Host-implemented save/load
        ##
        ## **mark_dirty** *main-thread*
        ## Tell the host that the plugin state has changed and should be saved again.
        ## If a parameter value changes, then it is implicit that the state is dirty.
        ##
        mark_dirty*: proc (host: ptr ClapHost): void {.cdecl.}
