# nim-clap
clap plugin api in nim. currently unfinished but includes all the basics

install with `nimble install clap`

**i have moved the plugin framework which abstracts over the raw api to [a new repo, offbeat](https://github.com/NimAudio/offbeat).**

---

tested with version 1.2, hash df8f16c. later versions may not work, try this version if you have any issues

has futhark set up but commented out. to use, put clap repo files in `clap-main` folder, not as a folder in that folder

### supported extensions:
- audio ports
- note ports
- parameters
- latency
- logging
- state
- gui
- timers

### known missing api sections (PRs welcome):
- transport events
- thread checking (basically empty file)
- definitely others

### building
to build, run the following command
```
nim compile --out:"example" --app:lib --threads:on ".../nim_clap/example.nim"
```
or for debugging
```
nim compile --verbosity:1 --hints:off --out:"example" --app:lib --forceBuild
--threads:on --lineDir:on --lineTrace:on --debuginfo:on ".../nim_clap/example.nim"
```

#### mac
then copy the binary (and .dSYM if debugging) into the provided example.clap bundle for macos. if you change the filename, you will need to change the bundle plist to have the updated name.

#### other platforms
i am not sure what is needed for windows or linux, but reaper at least doesn't care if it is bundled or not. i simply copied and modified the surge bundle.

### documentation
to view existing generated documentation
- run `python3 -m http.server 7029 --directory htmldocs`
- visit http://localhost:7029/clap.html

to generate documentation
- run `nim doc --project --index:on --outdir:htmldocs src/clap.nim`
