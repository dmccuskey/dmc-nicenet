# Changelog

## 2.0.0 (2026-10-02)

The module is ported to the current DMC libraries, and returns one ready queue instead of the class, as Solar2D has one `network`: call `nicenet.request()`, with a dot like `network.request()` (it was a method, `nn:request()`); the class is `nicenet.NiceNetwork`.

### Fixed

- Every call works again: the queue's handlers used an undefined global `cmd` and crashed.
- `download()` and `upload()` without a params table no longer crash.
- `upload()` calls `network.upload()`; it was queued as a download.
- The caller's listener runs before the next call starts and before the command changes state; an error in it still moves the queue on.
- Calls of the same priority run first in first out; before, in no set order.
- `cancel()` on a waiting call no longer crashes and takes it out of the queue; a running call is cancelled on the network too.
- `params.timeout` is in seconds, as for `network.request()` (it was milliseconds), and a timeout cancels the network call instead of leaving it running; the listener gets `isError = true`, `status = -1`, `url` and `timedOut = true`.
- `removeSelf()` cancels every call, waiting or running.
- A `network` call that raises (bad arguments) fails its command and the queue moves on, instead of stopping the queue.
- No more globals (`_extend`, `LOCAL_DEBUG`); dmc-utils is no longer required.

### Added

- `nicenet.makeGlobal()` and `nicenet.restoreGlobal()`: the queue behind the global `network` (issue #1), by replacing its `request`, `download`, `upload` and `cancel` in place, so code holding a reference to `network` goes through the queue too; and `MAKE_GLOBAL` in the cfg's `[DMC_NICENET]` section, which was defined but unused.
- `nicenet.cancel( requestId )`, like `network.cancel()`; `event.requestId` is the call's command.
- Progress events (`began`, `progress`) reach the listener.
- `params.priority`, a call's priority when it's made; the default priority is `MEDIUM` (it was `LOW`), so a call can be made more or less urgent than a normal one.
- `active_queue_limit` and `default_priority` getters and setters.
- `DEBUG_ACTIVE` in the cfg: prints each call as it's queued, started and done; a NiceNetwork's `debug_on` param.
- `VERSION`, `nicenet.NiceNetwork.NetworkCommand`, and the `Documentation:` link in the header.
- Unit tests (stand-in `timer` and `network`), and `tests/run_unit.sh` to run them with plain Lua 5.1.
- A Snakefile, the built `dmc_corona/`, and an example app, `examples/dmc-nicenet-queue`, on a dmc-mockserver mock server.

### Removed

- The class as the module's return value (now `nicenet.NiceNetwork`).
- Commands are no longer removed (`removeSelf()`) when done, so one stays usable as the event's `requestId`.

## 0.11.2 (2015-02-07)

The last version in this repository before 2.0.0, on `newClass`. (The 1.1.0 copy in DMC-Corona-Library, from 2014, is an older design on `inheritsFrom`.)
