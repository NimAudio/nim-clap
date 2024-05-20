import clap/[
            audioports,
            entry,
            events,
            factory,
            gui,
            latency,
            log,
            noteports,
            params,
            process,
            shared,
            state,
            threadcheck
        ]

# import futhark

# Tell futhark where to find the C libraries you will compile with, and what
# header files you wish to import.
# importc:
#     path "clap-main/include/clap"
#     "clap.h"

export
    audioports,
    entry,
    events,
    factory,
    gui,
    latency,
    log,
    noteports,
    params,
    process,
    shared,
    state,
    threadcheck

