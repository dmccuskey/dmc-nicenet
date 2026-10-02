--====================================================================--
-- dmc-nicenet-queue
--
-- queue requests by priority and watch them run, a few at a time;
-- a mock server answers them, so the example runs offline
--====================================================================--

print( "\n\n#########################################################\n\n" )



--====================================================================--
--== Imports


local json = require 'json'
local nicenet = require 'dmc_corona.dmc_nicenet'
local MockServer = require 'dmc_corona.dmc_mockserver'



--====================================================================--
--== Setup, Constants


local W, H = display.contentWidth, display.contentHeight
local H_CENTER = W*0.5

local API = 'https://api.example.com'

local PRIORITY = {
	[nicenet.HIGH]={ name="HIGH", letter='H', color={ 0.85, 0.25, 0.2 } },
	[nicenet.MEDIUM]={ name="MEDIUM", letter='M', color={ 0.9, 0.6, 0.1 } },
	[nicenet.LOW]={ name="LOW", letter='L', color={ 0.25, 0.45, 0.8 } },
}

local CHIP_W, CHIP_H, CHIP_GAP = 42, 28, 6
local CHIPS_PER_ROW = 6

local commands = {} -- in the order they were made

local active_group, pending_group, limit_txt, log_txt
local log_lines = {}

display.setDefault( 'background', 0.95, 0.95, 0.95 )



--====================================================================--
--== The Mock Server


-- every GET /items/<n> answers after 2 s with { "id": n }
local mock = MockServer:new{ delay=2000 }

mock:requestRespondWith( 'GET', '^/items/(%d+)$', {
	200, { ['Content-Type']='application/json' },
	function( url )
		return json.encode{ id=tonumber( url:match( '/items/(%d+)$' ) ) }
	end
})

-- nicenet's calls go to the mock server instead of Corona's network
nicenet.network = mock



--====================================================================--
--== Support Functions


local function log( text )
	print( text )
	table.insert( log_lines, 1, text )
	log_lines[7] = nil
	log_txt.text = table.concat( log_lines, "\n" )
end

-- a command's label: its priority's letter and its number, e.g. "L3"
local function label( cmd )
	return PRIORITY[ cmd.priority ].letter .. cmd.order
end

local function newChip( group, cmd, i )
	local col, row = ( i-1 ) % CHIPS_PER_ROW, math.floor( ( i-1 )/CHIPS_PER_ROW )
	local x = 20 + CHIP_W*0.5 + col*( CHIP_W+CHIP_GAP )
	local y = row*( CHIP_H+CHIP_GAP )
	local bg = display.newRoundedRect( group, x, y, CHIP_W, CHIP_H, 5 )
	bg:setFillColor( unpack( PRIORITY[ cmd.priority ].color ) )
	display.newText( group, label( cmd ), x, y, native.systemFontBold, 14 )
end

-- redraw a row of chips, in the order the queue runs them
local function showCommands( group, status )
	for i = group.numChildren, 1, -1 do group[i]:removeSelf() end
	local i = 0
	for _, priority in ipairs{ nicenet.HIGH, nicenet.MEDIUM, nicenet.LOW } do
		for _, cmd in ipairs( status[ priority ] ) do
			i = i+1
			newChip( group, cmd, i )
		end
	end
end

local function onQueueUpdate( event )
	if event.type ~= nicenet.QUEUE_UPDATE then return end
	showCommands( active_group, event.data.active )
	showCommands( pending_group, event.data.pending )
end

local function onResponse( event )
	local cmd = event.requestId
	if event.isError then
		log( label( cmd ) .. ": network error" )
	else
		log( label( cmd ) .. ": status " .. event.status .. " " .. event.response )
	end
end

local function addRequests( priority, n )
	-- without params.priority, a request gets nicenet.default_priority
	-- (MEDIUM); a waiting one's can be changed, cmd.priority = nicenet.HIGH
	for _ = 1, n do
		local cmd = nicenet.request( API .. '/items/' .. ( #commands+1 ), 'GET', onResponse, { priority=priority } )
		commands[ #commands+1 ] = cmd
	end
end

local function cancelNewest()
	for i = #commands, 1, -1 do
		local cmd = commands[i]
		if not cmd:isDone() then
			nicenet.cancel( cmd )
			log( label( cmd ) .. ": cancelled" )
			return
		end
	end
	log( "nothing to cancel" )
end

local function changeLimit()
	nicenet.active_queue_limit = nicenet.active_queue_limit % 3 + 1
	limit_txt.text = "Active (limit " .. nicenet.active_queue_limit .. ")"
	log( "limit " .. nicenet.active_queue_limit )
end

local function newButton( label, x, y, w, onTap )
	local bg = display.newRoundedRect( x, y, w, 36, 6 )
	bg:setFillColor( 0.3, 0.3, 0.35 )
	local txt = display.newText( label, x, y, native.systemFont, 15 )
	bg:addEventListener( 'tap', function() onTap() ; return true end )
	return bg, txt
end

local function newHeading( text, y )
	local t = display.newText{ text=text, x=20, y=y, font=native.systemFontBold, fontSize=14 }
	t.anchorX = 0
	t:setFillColor( 0.2, 0.2, 0.2 )
	return t
end



--====================================================================--
--== Main


local title = display.newText( "dmc-nicenet", H_CENTER, 30, native.systemFontBold, 20 )
title:setFillColor( 0.2, 0.2, 0.2 )

newButton( "+3 LOW", 60, 75, 90, function() addRequests( nicenet.LOW, 3 ) end )
newButton( "+1 MEDIUM", 160, 75, 90, function() addRequests( nicenet.MEDIUM, 1 ) end )
newButton( "+1 HIGH", 260, 75, 90, function() addRequests( nicenet.HIGH, 1 ) end )
newButton( "Limit 1/2/3", 85, 120, 140, changeLimit )
newButton( "Cancel newest", 235, 120, 140, cancelNewest )

limit_txt = newHeading( "Active (limit " .. nicenet.active_queue_limit .. ")", 165 )
active_group = display.newGroup()
active_group.y = 195

newHeading( "Pending, in the order they run", 230 )
pending_group = display.newGroup()
pending_group.y = 260

newHeading( "Responses, newest first", 350 )
log_txt = display.newText{ text="add some requests", x=20, y=368, width=280, font=native.systemFont, fontSize=12 }
log_txt.anchorX, log_txt.anchorY = 0, 0
log_txt:setFillColor( 0.1, 0.1, 0.1 )

nicenet:addEventListener( nicenet.EVENT, onQueueUpdate )
