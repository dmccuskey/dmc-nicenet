--====================================================================--
-- dmc_corona/dmc_nicenet.lua
--
-- A better behaved network object for the Corona SDK
--
-- Documentation:
--====================================================================--

--[[

The MIT License (MIT)

Copyright (C) 2013-2015 David McCuskey. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]



--====================================================================--
--== DMC Corona Library : DMC NiceNet
--====================================================================--


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.11.2"



--====================================================================--
--== DMC Corona Library Config
--====================================================================--



--====================================================================--
--== Support Functions


local Utils = {} -- make copying from dmc_utils easier

function Utils.extend( fromTable, toTable )

	function _extend( fT, tT )

		for k,v in pairs( fT ) do

			if type( fT[ k ] ) == "table" and
				type( tT[ k ] ) == "table" then

				tT[ k ] = _extend( fT[ k ], tT[ k ] )

			elseif type( fT[ k ] ) == "table" then
				tT[ k ] = _extend( fT[ k ], {} )

			else
				tT[ k ] = v
			end
		end

		return tT
	end

	return _extend( fromTable, toTable )
end



--====================================================================--
--== Configuration


local dmc_lib_data

-- boot dmc_corona with boot script or
-- setup basic defaults if it doesn't exist
--
if false == pcall( function() require( 'dmc_corona_boot' ) end ) then
	_G.__dmc_corona = {
		dmc_corona={},
	}
end

dmc_lib_data = _G.__dmc_corona




--====================================================================--
--== DMC NiceNet
--====================================================================--



--====================================================================--
--== Configuration


dmc_lib_data.dmc_nicenet = dmc_lib_data.dmc_nicenet or {}

local DMC_NICENET_DEFAULTS = {
	debug_active=false,
	make_global=false
}

local dmc_nicenet_data = Utils.extend( dmc_lib_data.dmc_nicenet, DMC_NICENET_DEFAULTS )



--====================================================================--
--== Imports


local Objects = require 'dmc_objects'
local Utils = require 'dmc_utils'



--====================================================================--
--== Setup, Constants


-- setup some aliases to make code cleaner
local newClass = Objects.newClass
local ObjectBase = Objects.ObjectBase



--====================================================================--
--== Network Command Class
--====================================================================--


local NetworkCommand = newClass( ObjectBase, {name="Network Command"} )

--== Class Constants

-- priority constants
NetworkCommand.HIGH = 1
NetworkCommand.MEDIUM = 2
NetworkCommand.LOW = 3

-- priority constants
NetworkCommand.TYPE_DOWNLOAD = 'network_download'
NetworkCommand.TYPE_REQUEST = 'network_request'
NetworkCommand.TYPE_UPLOAD = 'network_upload'

-- priority constants
NetworkCommand.STATE_PENDING = 'state_pending' -- ie, not yet active
NetworkCommand.STATE_UNFULFILLED = 'state_unfulfilled'
NetworkCommand.STATE_RESOLVED = 'state_resolved'
NetworkCommand.STATE_REJECTED = 'state_rejected'
NetworkCommand.STATE_CANCELLED = 'state_cancelled'

--== Event Constants

NetworkCommand.EVENT = 'network-command-event'

NetworkCommand.STATE_UPDATED = 'state-updated'
NetworkCommand.PRIORITY_UPDATED = 'priority-updated'


--======================================================--
-- Start: Setup DMC Objects

function NetworkCommand:__init__( params )
	--print( "NetworkCommand:__init__ ", params )
	params = params or {}
	self:superCall( '__init__', params )
	--==--

	--== Create Properties ==--

	self._params = params
	self._type = params.type
	self._state = self.STATE_PENDING
	self._priority = params.priority or self.LOW

	self._timeout = params.timeout ~= nil and params.timeout or 0
	self._timeout_timer = nil

	self._command = params.command
	-- url
	-- method
	-- listener
	-- params

	self._net_id = nil -- id from network.* call, can use to cancel
	self._network = nil -- network object to use, set on execute()

end


--[[
-- __initComplete__()
--
function NetworkCommand:__initComplete__()
	--print( "NetworkCommand:__initComplete__" )
	self:superCall( '__initComplete__' )
	--==--
end

function NetworkCommand:_undoInitComplete()
	--print( "NetworkCommand:_undoInitComplete" )
	--==--
	self:superCall( "_undoInitComplete" )
end
--]]

-- END: Setup DMC Objects
--======================================================--



--====================================================================--
--== Public Methods


function NetworkCommand.__getters:key()
	--print( "NetworkCommand.__getters:key" )
	return tostring( self )
end



-- getter/setter, command type
--
function NetworkCommand.__getters:type()
	--print( "NetworkCommand.__getters:type" )
	return self._type
end


-- getter/setter, command priority
--
function NetworkCommand.__getters:priority()
	--print( "NetworkCommand.__getters:priority" )
	return self._priority
end
function NetworkCommand.__setters:priority( value )
	--print( "NetworkCommand.__setters:priority ", value )
	if self._priority == value then return end
	self._priority = value
	self:dispatchEvent( NetworkCommand.PRIORITY_UPDATED )
end


-- getter/setter, command state
function NetworkCommand.__getters:state()
	--print( "NetworkCommand.__getters:state" )
	return self._state
end
function NetworkCommand.__setters:state( value )
	--print( "NetworkCommand.__setters:state ", value )
	if self._state == value then return end
	self._state = value
	self:dispatchEvent( NetworkCommand.STATE_UPDATED )
end


function NetworkCommand.__setters:network( value )
	--print( "NetworkCommand.__setters:network ", value )
	if value == nil then return end
	self._network = value
end



-- execute
-- start the network call
--
function NetworkCommand:execute( _network )
	--print( "NetworkCommand:execute" )
	assert( _network, "NetworkCommand:execute requires a network object" )
	--==--
	local t = self._type
	local p = self._command

	self.network = _network

	-- Setup basic Corona network.* callback

	local callback = function( event )
		-- capture original return or timeout
		if self.state ~= self.STATE_UNFULFILLED then return end

		-- set Command Object next state
		if event.isError then
			self.state = self.STATE_REJECTED
		else
			self.state = self.STATE_RESOLVED
		end

		self:_stopTimer()
		-- do upstream callback
		if p.listener then p.listener( event ) end

	end

	self:_startTimer( callback )


	-- Set Command Object active state and
	-- call appropriate Corona network.* function

	self.state = self.STATE_UNFULFILLED

	if t == self.TYPE_REQUEST then
		self._net_id = _network.request( p.url, p.method, callback, p.params )

	elseif t == self.TYPE_DOWNLOAD then
		self._net_id = _network.download( p.url, p.method, callback, p.params, p.filename, p.basedir )

	elseif t == self.TYPE_UPLOAD then
		self._net_id = _network.upload( p.url, p.method, callback, p.params, p.filename, p.basedir, p.contenttype )

	end

end


-- cancel
-- cancel the network call
--
function NetworkCommand:cancel()
	--print( "NetworkCommand:cancel" )
	if self.state == self.STATE_CANCELLED then return end

	self._network.cancel( self._net_id )
	self._net_id = nil
	self:_stopTimer()
	self.state = self.STATE_CANCELLED
end



--====================================================================--
--== Private Methods


function NetworkCommand:_startTimer( callback )
	-- print( "NetworkCommand:_startTimer" )

	if self._timeout == 0 then return end

	self:_stopTimer()

	local tof, tot

	tof = function()
		if LOCAL_DEBUG then
			print( "NiceNet: Forced command timeout" )
		end
		local e = {
			isError=true
		}
		callback(e)
	end

	tot = timer.performWithDelay( self._timeout, tof )
	self._timeout_timer = tot

end

function NetworkCommand:_stopTimer()
	-- print( "NetworkCommand:_stopTimer" )
	if self._timeout_timer == nil then return end
	timer.cancel( self._timeout_timer )
	self._timeout_timer = nil
end



--====================================================================--
--== Event Handlers


-- none




--====================================================================--
--== Nice Network Base Class
--====================================================================--


local NiceNetwork = newClass( ObjectBase, {name="Nice Network"} )

--== Class Constants

-- priority constants
NiceNetwork.HIGH = NetworkCommand.HIGH
NiceNetwork.MEDIUM = NetworkCommand.MEDIUM
NiceNetwork.LOW = NetworkCommand.LOW

NiceNetwork.DEFAULT_ACTIVE_QUEUE_LIMIT = 2
NiceNetwork.MIN_ACTIVE_QUEUE_LIMIT = 1

--== Event Constants

NiceNetwork.EVENT = 'nicenet-event'

NiceNetwork.QUEUE_UPDATE = 'queue-updated-event'


--======================================================--
-- Start: Setup DMC Objects

function NiceNetwork:__init__( params )
	--print( "NiceNetwork:__init__" )
	params = params or {}
	self:superCall( '__init__', params )
	--==--

	--== Create Properties ==--

	self._params = params
	self._default_priority = params.default_priority or NiceNetwork.LOW

	-- TODO: hook this up to params
	self._active_limit = params.active_queue_limit or self.DEFAULT_ACTIVE_QUEUE_LIMIT

 	-- dict of Active Command Objects, keyed on object raw id
 	self._active_queue = nil

 	-- dict of Pending Command Objects, keyed on object raw id
 	self._pending_queue = nil

 	-- save network object, param or global
 	self._network = params.network or _G.network
 	self._netCmd_f = nil -- callback for network command objects
end


-- __initComplete__()
--
function NiceNetwork:__initComplete__()
	--print( "NiceNetwork:__initComplete__" )
	self:superCall( '__initComplete__' )
	--==--
	-- create data structure
	self._active_queue = {}
	self._pending_queue = {}

	self._netCmd_f = self:createCallback( self._networkCommandEvent_handler )
end

function NiceNetwork:__undoInitComplete__()
	--print( "NiceNetwork:__undoInitComplete__" )
	self._netCmd_f=nil
	-- remove data structure
	self._active_queue = nil
	self._pending_queue = nil
	--==--
	self:superCall( '__undoInitComplete__' )
end

-- END: Setup DMC Objects
--======================================================--



--====================================================================--
--== Public Methods



function NiceNetwork.__setters:network( value )
	-- print( "NiceNetwork.__setters:network ", value )
	self._network = value
end
function NiceNetwork.__getters:network()
	-- print( "NiceNetwork.__getters:network " )
	return self._network
end


-- request()
-- this is a replacement for Corona network.request()
--[[
network.request( url, method, listener [, params] )
--]]
function NiceNetwork:request( url, method, listener, params )
	-- print( "NiceNetwork:request ", url, method )
	params = params or {}
	--==--

	--== Setup and create Command object

	local net_params, cmd_params

	-- save parameters for Corona network.* call
	net_params = {
		url=url,
		method=method,
		listener=listener,
		params=params
	}

	-- save parameters for NiceNet Command object
	cmd_params = {
		command=net_params,
		type=NetworkCommand.TYPE_REQUEST,
		priority=self._default_priority,
		timeout=params.timeout
	}

	return self:_insertCommandIntoQueue( cmd_params )
end


-- download()
-- this is a replacement for Corona network.download()
--[[
network.download( url, method, listener [, params], filename [, baseDirectory] )
--]]
function NiceNetwork:download( url, method, listener, params, filename, basedir )
	--print( "NiceNetwork:download ", url, filename )

	--== Process optional parameters

	-- network params
	if params and type(params) ~= 'table' then
		basedir = filename
		filename = params
		params = nil
	end

	--== Setup and create Command object

	local net_params, cmd_params

	-- save parameters for Corona network.* call
	net_params = {
		url=url,
		method=method,
		listener=listener,
		params=params,
		filename=filename,
		basedir=basedir
	}
	-- save parameters for NiceNet Command object
	cmd_params = {
		command=net_params,
		type=NetworkCommand.TYPE_DOWNLOAD,
		priority=self._default_priority,
		timeout=params.timeout
	}

	return self:_insertCommandIntoQueue( cmd_params )
end


-- this is a replacement for Corona network.upload()
--[[
network.upload( url, method, listener [, params], filename [, baseDirectory] [, contentType] )
--]]
function NiceNetwork:upload( url, method, listener, params, filename, basedir, contenttype )

	--== Process optional parameters

	-- network params
	if params and type(params) ~= 'table' then
		contenttype = basedir
		basedir = filename
		filename = params
		params = nil
	end

	-- base directory
	if basedir and type(basedir) ~= 'userdata' then
		contenttype = basedir
		basedir = nil
	end

	--== Setup and create Command object

	local net_params, cmd_params

	-- save parameters for Corona network.* call
	net_params = {
		url=url,
		method=method,
		listener=listener,
		params=params,
		filename=filename,
		basedir=basedir,
		contenttype=contenttype
	}
	-- save parameters for NiceNet Command object
	cmd_params = {
		command=net_params,
		type=NetworkCommand.TYPE_DOWNLOAD,
		priority=self._default_priority,
		timeout=params.timeout
	}

	return self:_insertCommandIntoQueue( cmd_params )
end



--====================================================================--
--== Private Methods


function NiceNetwork:_insertCommandIntoQueue( params )
	--print( "NiceNetwork:_insertCommandIntoQueue ", params.type )

	local net_command = NetworkCommand:new( params )
	net_command:addEventListener( net_command.EVENT, self._netCmd_f )
	self._pending_queue[ net_command.key ] = net_command

	self:_processQueue()

	return net_command
end

function NiceNetwork:_removeCommandFromQueue( net_command )
	--print( "NiceNetwork:_removeCommandFromQueue ", net_command.type )

	self._active_queue[ net_command.key ] = nil
	net_command:removeEventListener( net_command.EVENT, self._netCmd_f )
	net_command:removeSelf()

	self:_processQueue()
end


function NiceNetwork:_processQueue()
	--print( "NiceNetwork:_processQueue" )

	local pq_status, next_cmd

	if Utils.tableSize( self._active_queue ) < self._active_limit then
		-- we have slots left, checking for pending commands

		-- check status of pending queue
		pq_status = self:_checkStatus( self._pending_queue )

		-- pick next command
		if #pq_status[ NetworkCommand.HIGH ] > 0 then
			next_cmd = pq_status[ NetworkCommand.HIGH ][1]
		elseif #pq_status[ NetworkCommand.MEDIUM ] > 0 then
			next_cmd = pq_status[ NetworkCommand.MEDIUM ][1]
		elseif #pq_status[ NetworkCommand.LOW ] > 0 then
			next_cmd = pq_status[ NetworkCommand.LOW ][1]
		end

		if next_cmd ~= nil then
			self._active_queue[ next_cmd.key ] = next_cmd
			self._pending_queue[ next_cmd.key ] = nil
			next_cmd:execute( self.network )
		end
	end

	self:_broadcastStatus()
end


-- provide list of commands in queue for each priority
-- easy to get count of each type from a list
--
function NiceNetwork:_checkStatus( queue )

	local status = {}
	status[ NetworkCommand.LOW ] = {}
	status[ NetworkCommand.MEDIUM ] = {}
	status[ NetworkCommand.HIGH ] = {}

	for _, cmd in pairs( queue ) do
		table.insert( status[ cmd.priority ], cmd )
	end

	return status
end


-- _broadcastStatus()
-- count status, and send event
--
function NiceNetwork:_broadcastStatus()
	--print( "NiceNetwork:_broadcastStatus" )
	local data = {
		active = self:_checkStatus( self._active_queue ),
		pending = self:_checkStatus( self._pending_queue )
	}
	self:dispatchEvent( self.QUEUE_UPDATE, data )
end


-- _checkValidCommandState()
-- check current state, remove if necessary
--
function NiceNetwork:_checkValidCommandState( net_command )
	--print( "NiceNetwork:_checkValidCommandState" )
	local state = net_command.state

	if state == cmd.STATE_REJECTED or state == cmd.STATE_RESOLVED or state == cmd.STATE_CANCELLED then
		-- remove from Active queue
		self:_removeCommandFromQueue( cmd )
	end
end




--====================================================================--
--== Event Handlers


-- _networkCommandEvent_handler()
-- handle any events from Network Command objects
--
function NiceNetwork:_networkCommandEvent_handler( event )
	--print( "NiceNetwork:_networkCommandEvent_handler ", event.type )

	if event.type == cmd.PRIORITY_UPDATED then
		self:_broadcastStatus()

	elseif event.type == cmd.STATE_UPDATED then
		self:_checkValidCommandState( event.target )

	end
end




return NiceNetwork
