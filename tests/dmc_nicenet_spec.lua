--====================================================================--
-- tests/dmc_nicenet_spec.lua
--
-- unit tests for dmc_nicenet, with a stand-in timer and network;
-- timers fire only in fire(), network calls are answered in answer()
-- run with tests/run_unit.sh
--====================================================================--


module( ..., package.seeall )


--====================================================================--
--== Setup

-- the timer: performWithDelay() queues, fire() runs what's queued

local timers = {}

_G.timer = {
	performWithDelay=function( delay, f )
		local t = { delay=delay, f=f }
		table.insert( timers, t )
		return t
	end,
	cancel=function( t ) t.cancelled = true end,
}

local function fire()
	local list = timers
	timers = {}
	for _, t in ipairs( list ) do
		if not t.cancelled then t.f() end
	end
end

-- the network: records each call; answer( i ) calls its listener

local calls, cancels, ids

local function record( kind )
	return function( ... )
		ids = ids + 1
		local args = { ... }
		table.insert( calls, { kind=kind, id='net-'..ids, url=args[1], args=args } )
		return 'net-'..ids
	end
end

local net = {
	request=record( 'request' ),
	download=record( 'download' ),
	upload=record( 'upload' ),
	cancel=function( id ) table.insert( cancels, id ) ; return true end,
	setStatusListener=function() return 'status' end,
}

local function answer( i, event )
	event = event or { name='networkRequest', phase='ended', isError=false, status=200, response='ok' }
	event.requestId = event.requestId or calls[i].id
	local c = calls[i]
	c.args[3]( event )
end

local function urls()
	local list = {}
	for _, c in ipairs( calls ) do table.insert( list, c.url ) end
	return table.concat( list, ' ' )
end

_G.network = net

local nicenet = require 'dmc_corona.dmc_nicenet'
local NiceNet = nicenet.NiceNetwork
local Command = NiceNet.NetworkCommand

local nn, events

local function listener( event ) table.insert( events, event ) end

function setup()
	timers = {}
	calls = {}
	cancels = {}
	ids = 0
	events = {}
	_G.network = net
	nn = NiceNet:new( { network=net } )
end

function teardown()
	nicenet.restoreGlobal()
	_G.network = net
end


--====================================================================--
--== Tests


function test_version()
	assert_string( NiceNet.VERSION )
end

function test_request_answers_listener()
	local params = { headers={ A='1' } }
	local cmd = nn.request( 'http://x/a', 'GET', listener, params )
	assert_equal( 1, #calls )
	assert_equal( 'request', calls[1].kind )
	assert_equal( 'GET', calls[1].args[2] )
	assert_equal( params, calls[1].args[4] )
	assert_equal( Command.STATE_UNFULFILLED, cmd.state )
	answer( 1 )
	assert_equal( 1, #events )
	assert_equal( cmd, events[1].requestId )
	assert_equal( Command.STATE_RESOLVED, cmd.state )
end

function test_error_event_rejects()
	local cmd = nn.request( 'http://x/a', 'GET', listener )
	answer( 1, { isError=true, status=-1 } )
	assert_true( events[1].isError )
	assert_equal( Command.STATE_REJECTED, cmd.state )
end

function test_queue_limit()
	nn.request( 'http://x/1', 'GET', listener )
	nn.request( 'http://x/2', 'GET', listener )
	nn.request( 'http://x/3', 'GET', listener )
	assert_equal( 'http://x/1 http://x/2', urls() )
	answer( 2 )
	assert_equal( 'http://x/1 http://x/2 http://x/3', urls() )
end

function test_listener_runs_before_next_starts()
	local seen
	nn.request( 'http://x/1', 'GET', function() seen = #calls end )
	nn.request( 'http://x/2', 'GET', listener )
	nn.request( 'http://x/3', 'GET', listener )
	answer( 1 )
	assert_equal( 2, seen )
	assert_equal( 3, #calls )
end

function test_same_priority_first_in_first_out()
	nn.active_queue_limit = 1
	for i = 1, 6 do nn.request( 'http://x/'..i, 'GET', listener ) end
	for i = 1, 5 do answer( i ) end
	assert_equal( 'http://x/1 http://x/2 http://x/3 http://x/4 http://x/5 http://x/6', urls() )
end

function test_default_priority_medium()
	assert_equal( NiceNet.MEDIUM, nn.default_priority )
	local cmd = nn.request( 'http://x/1', 'GET', listener )
	assert_equal( NiceNet.MEDIUM, cmd.priority )
end

function test_priority()
	nn.active_queue_limit = 1
	nn.request( 'http://x/1', 'GET', listener )
	nn.request( 'http://x/2', 'GET', listener )
	local c3 = nn.request( 'http://x/3', 'GET', listener )
	c3.priority = NiceNet.HIGH
	nn.default_priority = NiceNet.LOW
	nn.request( 'http://x/4', 'GET', listener )
	local c5 = nn.request( 'http://x/5', 'GET', listener, { priority=NiceNet.HIGH } )
	assert_equal( NiceNet.HIGH, c5.priority )
	for i = 1, 4 do answer( i ) end
	assert_equal( 'http://x/1 http://x/3 http://x/5 http://x/2 http://x/4', urls() )
end

function test_priority_param()
	nn.active_queue_limit = 1
	nn.request( 'http://x/1', 'GET', listener )
	nn.download( 'http://x/f', 'GET', listener, { priority=NiceNet.LOW }, 'f' )
	nn.upload( 'http://x/u', 'POST', listener, { priority=NiceNet.HIGH }, 'u' )
	answer( 1 ) ; answer( 2 )
	assert_equal( 'http://x/1 http://x/u http://x/f', urls() )
	assert_false( pcall( nn.request, 'http://x/2', 'GET', listener, { priority=7 } ) )
end

function test_download_without_params()
	local cmd = nn.download( 'http://x/f.png', 'GET', listener, 'f.png', 'Docs' )
	assert_equal( 'download', calls[1].kind )
	local a = calls[1].args
	assert_nil( a[4] )
	assert_equal( 'f.png', a[5] )
	assert_equal( 'Docs', a[6] )
	assert_equal( Command.TYPE_DOWNLOAD, cmd.type )
end

function test_download_with_params_and_timeout()
	nn.download( 'http://x/f.png', 'GET', listener, { timeout=4 }, 'f.png' )
	assert_equal( 4, calls[1].args[4].timeout )
	assert_equal( 4000, timers[1].delay )
end

function test_upload_calls_network_upload()
	local docs = {} -- a base directory, userdata in Solar2D
	local cmd = nn.upload( 'http://x/up', 'POST', listener, 'f.txt', docs, 'text/plain' )
	assert_equal( 'upload', calls[1].kind )
	assert_equal( Command.TYPE_UPLOAD, cmd.type )
	local a = calls[1].args
	assert_nil( a[4] )
	assert_equal( 'f.txt', a[5] )
	assert_equal( docs, a[6] )
	assert_equal( 'text/plain', a[7] )
end

function test_upload_content_type_without_basedir()
	nn.upload( 'http://x/up', 'POST', listener, { timeout=1 }, 'f.txt', 'text/plain' )
	local a = calls[1].args
	assert_equal( 'f.txt', a[5] )
	assert_nil( a[6] )
	assert_equal( 'text/plain', a[7] )
end

function test_cancel_pending()
	nn.active_queue_limit = 1
	nn.request( 'http://x/1', 'GET', listener )
	local c2 = nn.request( 'http://x/2', 'GET', listener )
	assert_true( nn.cancel( c2 ) )
	assert_false( c2:cancel() )
	assert_equal( Command.STATE_CANCELLED, c2.state )
	assert_equal( 0, #cancels ) -- never reached the network
	answer( 1 )
	assert_equal( 'http://x/1', urls() )
end

function test_cancel_active()
	nn.active_queue_limit = 1
	local c1 = nn.request( 'http://x/1', 'GET', listener )
	nn.request( 'http://x/2', 'GET', listener )
	assert_true( c1:cancel() )
	assert_equal( 'net-1', cancels[1] )
	assert_equal( 'http://x/1 http://x/2', urls() )
	answer( 1 ) -- a late answer is ignored
	assert_equal( 0, #events )
end

function test_cancel_passes_other_ids_on()
	nn.cancel( 'corona-id' )
	assert_equal( 'corona-id', cancels[1] )
end

function test_timeout_in_seconds()
	local cmd = nn.request( 'http://x/1', 'GET', listener, { timeout=5 } )
	assert_equal( 5000, timers[1].delay )
	fire()
	assert_equal( 1, #events )
	local e = events[1]
	assert_true( e.isError )
	assert_equal( -1, e.status )
	assert_true( e.timedOut )
	assert_equal( 'http://x/1', e.url )
	assert_equal( cmd, e.requestId )
	assert_equal( 'net-1', cancels[1] )
	assert_equal( Command.STATE_REJECTED, cmd.state )
	answer( 1 ) -- the real answer, too late
	assert_equal( 1, #events )
end

function test_answer_stops_timeout()
	nn.request( 'http://x/1', 'GET', listener, { timeout=5 } )
	answer( 1 )
	assert_true( timers[1].cancelled )
end

function test_progress_events_pass_through()
	local cmd = nn.download( 'http://x/f', 'GET', listener, { progress=true }, 'f' )
	answer( 1, { phase='began', isError=false } )
	answer( 1, { phase='progress', isError=false } )
	assert_equal( 2, #events )
	assert_equal( Command.STATE_UNFULFILLED, cmd.state )
	answer( 1 )
	assert_equal( Command.STATE_RESOLVED, cmd.state )
end

function test_listener_error_moves_queue_on()
	nn.active_queue_limit = 1
	local c1 = nn.request( 'http://x/1', 'GET', function() error( 'boom' ) end )
	nn.request( 'http://x/2', 'GET', listener )
	local ok, err = pcall( answer, 1 )
	assert_false( ok )
	assert_match( 'boom', err )
	assert_equal( Command.STATE_RESOLVED, c1.state )
	assert_equal( 2, #calls )
end

function test_network_call_error_moves_queue_on()
	local bad = { request=function( url ) if url=='bad' then error( 'bad url' ) end return 'id' end }
	nn.network = bad
	nn.active_queue_limit = 1
	local ok, err = pcall( nn.request, 'bad', 'GET', listener )
	assert_false( ok )
	assert_match( 'bad url', err )
	local c2 = nn.request( 'good', 'GET', listener )
	assert_equal( Command.STATE_UNFULFILLED, c2.state )
end

function test_active_queue_limit()
	assert_false( pcall( function() NiceNet:new( { network=net, active_queue_limit=0 } ) end ) )
	assert_false( pcall( function() nn.active_queue_limit = 0 end ) )
	nn.active_queue_limit = 1
	nn.request( 'http://x/1', 'GET', listener )
	nn.request( 'http://x/2', 'GET', listener )
	nn.request( 'http://x/3', 'GET', listener )
	assert_equal( 1, #calls )
	nn.active_queue_limit = 3
	assert_equal( 3, #calls )
end

function test_queue_update_event()
	local got
	nn:addEventListener( nn.EVENT, function( e )
		if e.type==nn.QUEUE_UPDATE then got = e.data end
	end )
	nn.request( 'http://x/1', 'GET', listener )
	nn.request( 'http://x/2', 'GET', listener )
	nn.request( 'http://x/3', 'GET', listener )
	assert_equal( 2, #got.active[ NiceNet.MEDIUM ] )
	assert_equal( 1, #got.pending[ NiceNet.MEDIUM ] )
	answer( 1 )
	assert_equal( 2, #got.active[ NiceNet.MEDIUM ] )
	assert_equal( 0, #got.pending[ NiceNet.MEDIUM ] )
end

function test_removeSelf_cancels_all()
	local c1 = nn.request( 'http://x/1', 'GET', listener )
	nn.request( 'http://x/2', 'GET', listener )
	local c3 = nn.request( 'http://x/3', 'GET', listener )
	nn:removeSelf()
	assert_equal( 2, #cancels )
	assert_equal( Command.STATE_CANCELLED, c1.state )
	assert_equal( Command.STATE_CANCELLED, c3.state )
	assert_equal( 2, #calls ) -- the pending one never started
end

function test_module_is_one_nicenetwork()
	assert_true( nicenet:isa( NiceNet ) )
	assert_equal( net, nicenet.network )
	assert_equal( NiceNet.VERSION, nicenet.VERSION )
	assert_equal( NiceNet.HIGH, nicenet.HIGH )
	nicenet.request( 'http://x/m', 'GET', listener )
	assert_equal( 'http://x/m', urls() )
	answer( 1 )
	assert_equal( 1, #events )
end

function test_make_global()
	local request = net.request
	local held = network -- held before makeGlobal(), as a library might
	nicenet.active_queue_limit = 1
	assert_equal( nicenet, nicenet.makeGlobal() )
	assert_equal( net, _G.network ) -- the same table, its calls replaced
	assert_equal( nicenet.request, net.request )
	assert_equal( nicenet, nicenet.makeGlobal() ) -- once
	held.request( 'http://x/1', 'GET', listener )
	local c2 = network.request( 'http://x/2', 'GET', listener )
	assert_true( c2:isa( Command ) )
	assert_equal( 1, #calls ) -- through the queue, not calling itself
	assert_true( held.cancel( c2 ) )
	assert_equal( Command.STATE_CANCELLED, c2.state )
	assert_equal( 'status', network.setStatusListener() ) -- left alone
	-- a network's own id goes on to its own cancel()
	assert_true( network.cancel( 'net-1' ) )
	assert_equal( 'net-1', cancels[1] )
	-- a new NiceNetwork on the global network calls its own calls too
	local other = NiceNet:new()
	assert_equal( net, other.network )
	other.request( 'http://x/o', 'GET', listener )
	assert_equal( 'http://x/1 http://x/o', urls() )
	assert_equal( nicenet, nicenet.restoreGlobal() )
	assert_equal( request, net.request )
	assert_nil( nicenet.restoreGlobal() )
	nicenet.active_queue_limit = NiceNet.DEFAULT_ACTIVE_QUEUE_LIMIT
end

function test_restore_global_keeps_queue()
	nicenet.active_queue_limit = 1
	nicenet.makeGlobal()
	network.request( 'http://x/1', 'GET', listener )
	network.request( 'http://x/2', 'GET', listener )
	nicenet.restoreGlobal()
	answer( 1 )
	assert_equal( 'http://x/1 http://x/2', urls() )
	assert_equal( 1, #events )
	answer( 2 )
	nicenet.active_queue_limit = NiceNet.DEFAULT_ACTIVE_QUEUE_LIMIT
end

function test_make_global_from_cfg()
	local request = net.request
	package.loaded[ 'dmc_corona.dmc_nicenet' ] = nil
	_G.__dmc_corona.dmc_nicenet.make_global = true
	local ok, mod = pcall( require, 'dmc_corona.dmc_nicenet' )
	_G.__dmc_corona.dmc_nicenet.make_global = false
	assert_true( ok, mod )
	assert_equal( net, _G.network )
	assert_equal( mod.request, net.request )
	mod.restoreGlobal()
	assert_equal( request, net.request )
	package.loaded[ 'dmc_corona.dmc_nicenet' ] = nicenet
end
