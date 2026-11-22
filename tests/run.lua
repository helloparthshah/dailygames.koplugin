-- Usage (from the repo root): luajit tests/run.lua tests/test_nyt.lua
-- Runs one test file against stubbed KOReader modules.
PLUGDIR = "."
STUBS = "tests/stubs.lua"
dofile(assert(arg[1], "pass a test file"))
