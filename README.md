# dmc-nicenet

A better behaved `network` for Solar2D (formerly Corona SDK) apps: requests wait in a queue, a few at a time, so the app doesn't flood the server or the connection.

dmc-nicenet has the same calls as Solar2D's `network` library and is ready when required: call it instead of `network`, or make it the global `network` so the code you have goes through the queue unchanged.

```lua
local nicenet = require 'dmc_corona.dmc_nicenet'

nicenet.request( 'https://example.com/', 'GET', function( event )
	print( event.status )  -- 200
end )
```

## Features

- `request()`, `download()`, `upload()` and `cancel()`, called like `network.request()`, `network.download()`, `network.upload()` and `network.cancel()`, with the same listener events
- A queue: at most `active_queue_limit` calls run at once (2 by default); the rest wait their turn, first in first out
- Priorities: `HIGH`, `MEDIUM` and `LOW`, per call or by default (`MEDIUM`, so a call can go either way); change a waiting call's priority and it moves in the queue
- Cancel a call that's waiting or running
- A timeout per call, in seconds, which ends it with a network error
- A queue update event, to show what's running and waiting
- A drop-in global: `nicenet.makeGlobal()`, or `MAKE_GLOBAL` in the cfg, puts the queue behind `network.request()` and the rest, for every module and plugin that calls them
- Any object with `network`'s calls behind it, such as a [dmc-mockserver](https://github.com/dmccuskey/dmc-mockserver) mock server, to build and test without a server
- MIT licensed

## Quick Start

The following code will get you up and running in about 10 minutes in the Solar2D Simulator on macOS or Windows. It makes an app that queues three requests, one at a time, then moves a fourth to the front of the queue.

Prerequisites: the [Solar2D](https://solar2d.com/) Simulator, a network connection, and a copy of this repository (`git clone https://github.com/dmccuskey/dmc-nicenet.git`, or download the ZIP from GitHub).

### 1. Copy the Library into Your Project

Copy these from this repository into the root of your project folder:

```text
dmc_corona_boot.lua     loader for the DMC libraries
dmc_corona.cfg          configuration
dmc_corona/             dmc-nicenet and the libraries it uses
```

**Going further:** keep the libraries in a subfolder, or combine several DMC libraries ([dmc-corona-boot Configuration](https://github.com/dmccuskey/dmc-corona-boot/blob/master/docs/configuration.md)).

### 2. Queue Some Requests

Create `main.lua` in the project folder:

```lua
local nicenet = require 'dmc_corona.dmc_nicenet'

-- one call at a time, to watch the order
nicenet.active_queue_limit = 1

local function onResponse( event )
	print( event.url, event.status )
end

for i = 1, 3 do
	nicenet.request( 'https://example.com/?page=' .. i, 'GET', onResponse )
end
```

Open `main.lua` in the Simulator. The first request starts at once, the others wait for the one before; the console shows:

```text
https://example.com/?page=1	200
https://example.com/?page=2	200
https://example.com/?page=3	200
```

### 3. Move One to the Front

Add this to the end of `main.lua`:

```lua
nicenet.request( 'https://example.com/?page=urgent', 'GET', onResponse, { priority=nicenet.HIGH } )
```

The Simulator restarts the app when the file is saved. The urgent request waits only for the one already running:

```text
https://example.com/?page=1	200
https://example.com/?page=urgent	200
https://example.com/?page=2	200
https://example.com/?page=3	200
```

To queue the `network.request()` calls an app already makes, call `nicenet.makeGlobal()` once, before them, or set `MAKE_GLOBAL` in the cfg (see [Configuration](#configuration)).

For a live view of the queue, cancelling and changing the limit, run offline on a mock server, see the [example](examples/README.md).

To update, copy `dmc_corona_boot.lua` and `dmc_corona/` again from the newer version. Keep your own `dmc_corona.cfg` if you have changed it.

## Reference

`require 'dmc_corona.dmc_nicenet'` returns the module's queue, a `NiceNetwork`, ready to use; like `network`, there is one, and nothing to create. Its class is `nicenet.NiceNetwork`, a [dmc-objects](https://github.com/dmccuskey/dmc-objects) `ObjectBase`, for a separate queue: `nicenet.NiceNetwork:new( params )`. `nicenet.VERSION` is the module's version (`"2.0.0"`).

### Calls

`nicenet.request( url, method, listener, params )`, `nicenet.download( url, method, listener, params, filename, baseDirectory )`, `nicenet.upload( url, method, listener, params, filename, baseDirectory, contentType )` and `nicenet.cancel( requestId )` take what Solar2D's take, with a dot, optional arguments included. Each call is queued, then passed to the network when its turn comes.

- The listener gets the network's events, `began` and `progress` phases included, with `event.requestId` set to the call's command (below). It runs before the next call starts; an error in it still moves the queue on, and is raised after.
- A call returns its command, a `NetworkCommand`, also the event's `requestId`.
- `params.priority` is the call's priority (see [Priority](#priority)); without it, the call gets `default_priority`; anything but `HIGH`, `MEDIUM` or `LOW` raises an error.
- `params.timeout` (seconds, as for `network.request()`) also starts a timer when the call begins: if the network hasn't answered by then, the call is cancelled and the listener gets an event with `isError = true`, `status = -1`, `url` and `timedOut = true`.
- A `network` call that raises (bad arguments) fails its command, the queue moves on, and the error is raised.
- `nicenet.cancel( command )` cancels a waiting or running call; its listener isn't called, as with `network.cancel()`. Returns `true`, or `false` when it was done already. Anything else is passed to the network's `cancel()`. Without `makeGlobal()`, cancel a nicenet call this way: Solar2D's `network.cancel()` doesn't know its command.

### Properties

| property | default | effect |
|---|---|---|
| `active_queue_limit` | `2` (`DEFAULT_ACTIVE_QUEUE_LIMIT`) | calls running at once, `1` or more; raising it starts waiting calls |
| `default_priority` | `nicenet.MEDIUM` | the priority of a call without `params.priority` |
| `network` | the global `network` | where calls go: anything with `network`'s calls, dot-callable, such as a dmc-mockserver mock server |

`nicenet.NiceNetwork:new( params )` takes the same as params, plus `debug_on` (default: the cfg's `DEBUG_ACTIVE`), which prints each call as it's queued, started and done. A new NiceNetwork uses the global `network`, and after `makeGlobal()` it makes Solar2D's own calls, not the module's queue.

`nicenet:removeSelf()` (on a NiceNetwork of your own) cancels every call it has.

### Priority

`nicenet.HIGH`, `nicenet.MEDIUM` and `nicenet.LOW` (`1`, `2`, `3`). Give a call its priority with `params.priority`; the rest get `default_priority`, `MEDIUM` unless changed, so a call can be made more or less urgent than a normal one. The next call to start is the waiting one of highest priority, first in first out among equals. Set a waiting call's `command.priority` to move it; a running call's priority changes nothing.

### Commands

The `NetworkCommand` a call returns (`nicenet.NiceNetwork.NetworkCommand`), the same object as the listener's `event.requestId`. It's live: its properties change as the call goes through the queue.

| | |
|---|---|
| `priority` | get or set, see above |
| `state` | `STATE_PENDING` (waiting), `STATE_UNFULFILLED` (running), then `STATE_RESOLVED`, `STATE_REJECTED` (a network error or timeout) or `STATE_CANCELLED` |
| `isDone()` | `true` once resolved, rejected or cancelled |
| `cancel()` | as `nicenet.cancel( command )` |
| `type` | `TYPE_REQUEST`, `TYPE_DOWNLOAD` or `TYPE_UPLOAD` |
| `order` | its number in its queue, counting from 1 |

A command sends `STATE_UPDATED` when its state changes and `PRIORITY_UPDATED` when a waiting command's priority does:

```lua
cmd:addEventListener( cmd.EVENT, function( event )
	if event.type == cmd.STATE_UPDATED then print( cmd.state ) end
end )
```

### Queue Event

A NiceNetwork sends `nicenet.QUEUE_UPDATE` when its queue changes, with the commands running and waiting per priority, each list in order:

```lua
nicenet:addEventListener( nicenet.EVENT, function( event )
	if event.type ~= nicenet.QUEUE_UPDATE then return end
	print( #event.data.active[ nicenet.MEDIUM ], #event.data.pending[ nicenet.HIGH ] )
end )
```

### The Global

`nicenet.makeGlobal()` replaces `request`, `download`, `upload` and `cancel` in Solar2D's `network` table itself with nicenet's, so every call goes through the queue, including from code that saved a reference to `network` before (`local network = network` in a module or plugin). `network.cancel()` then takes a command as well as a Solar2D request id. The other `network` functions (`network.setStatusListener()` and the rest) are left alone. Calling it again changes nothing. Returns the queue.

`nicenet.restoreGlobal()` puts Solar2D's own calls back; calls already queued still run. Returns the queue, or `nil` when it wasn't global.

## Configuration

The `[DMC_NICENET]` section of `dmc_corona.cfg` (see [dmc-corona-boot Configuration](https://github.com/dmccuskey/dmc-corona-boot/blob/master/docs/configuration.md) for the file's format):

| key | values | default | effect |
|---|---|---|---|
| `DEBUG_ACTIVE:BOOL` | `true`, `false` | `false` | prints each call as it's queued, started and done; a NiceNetwork's `debug_on` param overrides it |
| `MAKE_GLOBAL:BOOL` | `true`, `false` | `false` | calls `makeGlobal()` when dmc-nicenet is first required |

The `dmc_corona.cfg` in this repository has the section with the keys commented out. With `MAKE_GLOBAL`, require dmc-nicenet once at the top of `main.lua`, before any network call.

## Known Issues

- A dmc-mockserver mock server has no `upload()`: an upload through one fails its command with an error.

Fixed issues are listed in the [CHANGELOG](CHANGELOG.md).

## Development

Only `dmc_corona/dmc_nicenet.lua` is written in this repository. The rest of `dmc_corona/` and `dmc_corona_boot.lua` (and their copies in the example) are generated from [dmc-objects](https://github.com/dmccuskey/dmc-objects), [DMC-Lua-Library](https://github.com/dmccuskey/DMC-Lua-Library), [dmc-corona-boot](https://github.com/dmccuskey/dmc-corona-boot) and, for the example, [dmc-mockserver](https://github.com/dmccuskey/dmc-mockserver); fix them there, then rebuild. The copies are made by Snakemake from sibling checkouts (`../dmc-objects`, `../DMC-Corona-Library` for the shared rules, and so on). From this repository's root folder:

```sh
snakemake --cores 1 build_all
```

The tests are in `tests/dmc_nicenet_spec.lua` ([lunatest](https://github.com/silentbicycle/lunatest)). Run them with plain Lua 5.1, with stand-ins for `timer` (timers fire when the test says) and `network` (calls are recorded and answered when the test says); they need the `dkjson` rock:

```sh
tests/run_unit.sh
```

Then check the [example](examples/README.md) in the Solar2D Simulator: add requests of each priority, cancel one, change the limit.

## License

dmc-nicenet is released under the [MIT License](LICENSE).
