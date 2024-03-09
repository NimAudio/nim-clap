import nimclap/[shared, latency, state, log, threadcheck, audioports, noteports, process, events, factory]

import futhark

# Tell futhark where to find the C libraries you will compile with, and what
# header files you wish to import.
importc:
    path "clap-main/include/clap"
    "clap.h"

export shared, latency, state, log, threadcheck, audioports, noteports, process, events, factory
