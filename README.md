# nim-clap
clap plugin api in nim. currently unfinished but includes all the basics

install with `nimble install clap`

**i have moved the plugin framework which abstracts over the raw api to [a new repo, offbeat](https://github.com/morganholly/offbeat).**

---

tested with version 1.2, hash df8f16c. later versions may not work, try this version if you have any issues

has futhark set up but commented out. to use, put clap repo files in `clap-main` folder, not as a folder in that folder

most types are defined in clap ending with `_t`. this looks kinda ugly imo, and isn't necessary in nim, but futhark looks for whether the `_t` version is defined, so all types that end with `_t` are aliased to remove that, and where types are used, the aliased version is used.

### known missing api sections (PRs welcome):
- transport events
- gui
- definitely others

### building

#### mac
to build, run the following command
```
nim compile --out:"example2" --app:lib --threads:on ".../offbeat/example2.nim"
```
or for debugging
```
nim compile --verbosity:2 --hints:off --out:"example2" --app:lib --forceBuild --threads:on -
-lineDir:on --lineTrace:on --debuginfo:on ".../offbeat/example2.nim"
```
and copy the binary (and .dSYM if debugging) into the provided example2.clap bundle for macos. if you change the filename, you will need to change the bundle plist to have the updated name.

#### other platforms
i am not sure what is needed for windows or linux, but reaper at least doesn't care if it is bundled or not. i simply copied and modified the surge bundle.
