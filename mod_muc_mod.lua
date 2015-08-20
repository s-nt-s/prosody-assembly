local rooms = module:depends("muc").rooms;
if not rooms then
	module:log("error", "This module only works on MUC components!");
	return;
end

local jid_split, jid_bare = require "util.jid".split, require "util.jid".bare;
local st = require "util.stanza";

local function alert(event, msg)
	local origin, stanza = event.origin, event.stanza;
	local reply = st.error_reply(stanza, "wait", "policy-violation");
	reply:up():tag("body"):text(msg):up();
	local x = stanza:get_child("x","http://jabber.org/protocol/muc");
	if x then
		reply:add_child(st.clone(x));
	end
	origin.send(reply);
end
local function brd(room,msg,origin)
	local stanza;
	if origin then
--		stanza = st.message({from=room.jid;type="groupchat";}, msg);
--		origin.send(stanza);
--		return;
	end
	stanza = st.message({from=room.jid;type="groupchat"}, msg);
	room:broadcast_message(stanza,true)
end
local function isin(value,items)
	for _,v in pairs(items) do
	  if v == value then return true; end
	end
	return false;
end
local function getNick(room,jid)
	local nick=room._jid_nick[jid];
	if nick then
		return nick:gsub("^.+\/", "");
	end
	return "<" .. jid:gsub("@.+$", "") .. ">";
end
local function showTurns(room,a,z)
	local queue =room.queue;
	local z=table.getn(queue);
	local tr=getNick(room,queue[1]);
	if z==1 then return tr; end
	for i=2,z-1,1 do
		tr= tr .. ", " .. getNick(room,queue[i]);
	end
	return tr .. " y " .. getNick(room,queue[z]);
end
function turno(room)
	brd(room,getNick(room,room.queue[1]) .. ", es tu turno");--. Escribe !end al terminar. Si pasa más de un minuto sin hablar los demás usuarios podran revocar tu turno escribiendo !eo!");
end
local function del(value,room)
	local queue =room.queue;
	if (not queue or table.getn(queue) == 0) then return; end
	local b = (queue[1] == value);
	for i=#queue,1,-1 do
		if queue[i] == value then
			table.remove(queue, i);
		end
	end
	if b then
		while table.getn(queue) > 0 and not room._occupants[room._jid_nick[queue[1]]] do
			table.remove(queue, 1);
		end;
	end
	if table.getn(queue) == 0 then
		brd(room,"No hay más turnos");
	elseif b then
		turno(room);
	end
end
local function enough(room,min)
	local count = 0;
	for _ in pairs(room._occupants) do 
		count = count + 1;
		if (count>=min) then return true; end
	end
	return false;
end

local function moderate(event)
	local origin, stanza = event.origin, event.stanza;
	if (stanza.attr.type ~= "groupchat") then return; end
	local dest_room, dest_host = jid_split(stanza.attr.to);
	local room = rooms[dest_room.."@"..dest_host];
	if not room then return; end
	local from_jid = stanza.attr.from;
	local nick=getNick(room,from_jid); --room._jid_nick[from_jid]:gsub("^.+\/", "");

	local body = stanza:get_child_text("body");
	if not body then return; end
	body=body:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1");

    if body == "!acta" then
            brd(room,nick .. ", puedes ver el acta en http://" .. dest_host .. ":5280/muc_log/" .. dest_room .. "/", origin);
            return true;
    end
	
	if not enough(room,2) then
		alert(event, "Una asamblea necesita al menos dos personas");
		return true;
	end

	if (body == "+1" or  body == "-1") then return; end
	if (body:sub(1,7)=="!matiz ") then
		local aux=body:gsub("https?:%/%/[^%s]+", "");
		if body:len() < 100 then return; end
		alert(event, "Un matiz no puede tener más de 100 caracteres");
	end

	local queue = room.queue;
	if not room.queue then
		queue = {};
		room.queue = queue;
	end

	if body == "!turn" then
		if isin(from_jid,queue) then
			alert(event, "Ya se anoto tu turno de palabra, se paciente. Turnos: " .. showTurns(room));
			return true;
		end
		if table.getn(queue) == 0 then
			room.lastmsg=os.time();
		end
		-- put from_jid in queue
		table.insert(queue, from_jid);
		if from_jid == queue[1] then
			turno(room);
			--brd(room,nick .. ", has de escribir !end al terminar tu turno", origin);
		else
			brd(room,nick .. ", tu turno ha sido apuntado. El orden de los turnos es: " .. showTurns(room), origin);
		end
		return true;
	end
	if body == "!end" then
		del(from_jid,room);
		room.lastmsg=os.time();
		return true;
	end
--	if body == "?turn" then
--		if table.getn(queue) == 0 then
--			brd(room,nick .. ", no hay turnos de palabra", origin);
--		else
--			brd(room,nick .. ", el orden de los turnos es: " .. showTurns(room), origin);
--		end
--		return true;
--	end

	-- Check if from_jid is his turn to speak
	if table.getn(queue) > 0 and from_jid == queue[1] then 
		room.lastmsg=os.time();
		return; 
	end
	if body == "!eo!" and table.getn(queue) > 0 and room.lastmsg then
		local diff=os.difftime(os.time(),room.lastmsg);
		local nk=getNick(room,queue[1]);
		if diff < 30 then
			alert(event, nk .. " hablo hace " .. diff .. " segundos, se paciente");
			return true;
		end
		local intr=math.max((60-diff),10);
		brd(room, nk .. " perdera el turno si no habla en los proximos " .. intr .. " segundos");
		module:add_timer(intr, function()
			local d=os.difftime(os.time(),room.lastmsg);
			if diff > 60 then
				del(queue[1],room);
			end
		end);
		return true;
	end

	alert(event, "Para hablar tienes que pedir turno escribiendo !turn");
	return true;
end
function caduca()

end

function leave(event)
	local origin, stanza = event.origin, event.stanza;
	local dest_room, dest_host = jid_split(stanza.attr.to);
	local room = rooms[dest_room.."@"..dest_host];
	local from_jid = stanza.attr.from;
	if not room or not room.queue or table.getn(room.queue) == 0 or from_jid ~= room.queue[1] then return; end
	del(from_jid,room);
end
function join(event)
	local origin, stanza = event.origin, event.stanza;
	local dest_room, dest_host = jid_split(stanza.attr.to);
	local room = rooms[dest_room.."@"..dest_host];
	local from_jid = stanza.attr.from;
--	module:log("info", "1-wellcoming! " .. from_jid);
	if not room then return; end
	
--	module:log("info", "2-wellcoming! " .. from_jid);

	local nick=getNick(room,from_jid);
	local msg="Bienvenido " .. nick .. ", esto es una asamblea y para hablar hay que pedir turno de palabra escribiendo !turn\n" ..
		"Para consultar los turnos de palabra actuales escribe ?turn\n" ..
		"Para expresar un matiz sin tener turno de palabra escribe al inicio de la frase !matiz";
	local rp = st.message({from=room.jid;type="groupchat";to=from_jid}, msg);
	module:send(rp);
	local rp2 = st.message({from=room.jid;type="groupchat";to=jid_bare(from_jid)}, msg);
	module:send(rp2);
	brd(room,msg,origin);
end
function joinleave(event)
	local origin, stanza = event.origin, event.stanza;
	if (stanza.name == "presence" and stanza.attr.type == "unavailable") then
		leave(event);
		return;
	end
	if (stanza.name == "presence" and not stanza.attr.type) then
--		join(event);
		return;
	end
end

function module.unload()
	for room_jid, room in pairs(rooms) do
		room.queue = nil;
		room.lastmsg = nil;
	end
end

module:hook("message/bare", moderate, 501);
module:hook("message/full", moderate, 501);
--module:hook("muc-occupant-joined", join); 
--module:hook("muc-occupant-left", leave);
module:hook("presence/bare", joinleave, 1);
module:hook("presence/full", joinleave, 1);

module:log("mod", "muc_mod loaded!");

--local muc = module:depends("muc");
--function muc.new_room(jid, config)
--	return setmetatable({
--		jid = jid;
--		_jid_nick = {};
--		_occupants = {};
--		_data = {
--			logging = true;
--			hidding = false;
--			whois = 'moderators';
--			history_length = math.min((config and config.history_length)
--				or default_history_length, max_history_length);
--			};
--		_affiliations = {};
--	}, room_mt);
--end

