# nim-clap
clap plugin api in nim. currently unfinished

**i have moved the plugin framework which abstracts over the raw api to [a new repo, offbeat](https://github.com/morganholly/offbeat).**

put clap repo files in `clap-main` folder, not as a folder in that folder

tested with version 1.2, hash df8f16c. later versions may not work, try this version if you have any issues

requires futhark

i have skipped over the types for transport related stuff. eventually i'll add that but i'm primarily making this for me and what i'm working on, which does not need that.

most types are defined in clap ending with `_t`. this looks kinda ugly imo, and isn't necessary in nim, but futhark looks for whether the `_t` version is defined, so all types that end with `_t` are aliased to remove that, and where types are used, the aliased version is used.
