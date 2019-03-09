require "wait"
room_not_in_database = {}
-- This section is almost a straight rip from Fiendish's aard_GMCP_mapper.xml all credit goes to him
local bit = require("bit")
function load_room_from_database (uid)
    local room
    local u = tostring(uid)
    assert (uid, "No UID supplied to load_room_from_database")
    -- if not in database, don't look again
    if room_not_in_database [u] then
        return nil
    end -- no point looking
    -- print('here?')
    for row in dbnrowsWRAPPER(string.format ("SELECT * FROM rooms WHERE uid = %s", fixsql (u))) do
        room = {
            name = row.name,
            area = row.area,
            building = row.building,
            terrain = row.terrain,
            info = row.info,
            notes = row.notes,
            x = row.x or 0,
            y = row.y or 0,
            z = row.z or 0,
            noportal = row.noportal,
            norecall = row.norecall,
            exits = {},
            exit_locks = {},
        ignore_exits_mismatch = (row.ignore_exits_mismatch == 1)}
        for exitrow in dbnrowsWRAPPER(string.format ("SELECT * FROM exits WHERE fromuid = %s", fixsql (u))) do
            room.exits [exitrow.dir] = tostring (exitrow.touid)
            room.exit_locks [exitrow.dir] = tostring(exitrow.level)
        end -- for each exit
    end -- finding room
    if room then
        if not rooms then
            -- this shouldn't even be possible. what the hell.
            rooms = {}
        end
        rooms [u] = room
        for row in dbnrowsWRAPPER(string.format ("SELECT * FROM bookmarks WHERE uid = %s", fixsql (u))) do
            rooms [u].notes = row.notes
        end -- finding room
        --tprint(room)
        return room
    end -- if found
    -- room not found in database
    room_not_in_database [u] = true
    return nil
end -- load_room_from_database
forced_opened = false
force_nests = 0
function sanitize_filename(str)
    str = string.gsub(str, "[^%w%s()_-]", "")
    return Trim(str)
end
worldPath = GetInfo(66)..sanitize_filename(WorldName())
db = assert (sqlite3.open(worldPath..".db"))
db:busy_timeout(100)
function forceOpenDB()
    force_nests = force_nests + 1
    if not db:isopen() then
        forced_opened = true
        -- print("Forcing open")
        db = assert (sqlite3.open(GetInfo (66) .. sanitize_filename(WorldName()) .. ".db"))
    end
end
function dbnrowsWRAPPER(query)
    forceOpenDB()
    iter, vm, i = db:nrows(query)
    local function itwrap(vm, i)
        retval = iter(vm, i)
        if not retval then
            closeDBifForcedOpen()
            return nil
        end
        return retval
    end
    return itwrap, vm, i
end
function closeDBifForcedOpen()
    force_nests = force_nests - 1
    if forced_opened and (force_nests <= 0) then
        force_nests = 0
        forced_opened = false
        db:close()
    end
end
function findNearestJumpRoom(src, dst, target_type)
    local depth = 0
    local max_depth = 500
    local room_sets = {}
    local rooms_list = {}
    local found = false
    local ftd = {}
    local destination = ""
    local next_room = 0
    local visited = ""
    local path_type = ""
    table.insert(rooms_list, fixsql(src))
    while not found and depth < max_depth do
        depth = depth + 1
        -- prune the search space
        if visited ~= "" then
            visited = visited..","..table.concat(rooms_list, ",")
        else
            visited = table.concat(rooms_list, ",")
        end
        -- get all exits to any room in the previous set
        local q = string.format ("select fromuid, touid, dir, norecall, noportal from exits,rooms where rooms.uid = exits.touid and exits.fromuid in (%s) and exits.touid not in (%s) and exits.level <= %s order by length(exits.dir) asc",
        table.concat(rooms_list, ","), visited, mylevel)
        local dcount = 0
        for row in dbnrowsWRAPPER(q) do
            dcount = dcount + 1
            table.insert(rooms_list, fixsql(row.touid))
            -- ordering by length(dir) ensures that custom exits (always longer than 1 char) get
            -- used preferentially to normal ones (1 char)
            if ((bounce_portal ~= nil or target_type == "*") and row.noportal ~= 1) or ((bounce_recall ~= nil or target_type == "**") and row.norecall ~= 1) or row.touid == dst then
                path_type = ((row.touid == dst) and 1) or ((((row.noportal == 1) and 2) or 0) + (((row.norecall == 1) and 4) or 0))
                -- path_type 1 means walking to the destination is closer than bouncing
                -- path_type 2 means the bounce room allows recalling but not portalling
                -- path_type 4 means the bounce room allows portalling but not recalling
                -- path_type 0 means the bounce room allows both portalling and recalling
                destination = row.touid
                found = true
                found_depth = depth
            end -- if src
        end -- for select
        if dcount == 0 then
            return -- there is no path to a portalable or recallable room
        end -- if dcount
    end -- while
    if found == false then
        return
    end
    return destination, path_type, found_depth
end
function findpath(src, dst, noportals, norecalls)
    local rooms = {}
    if mylevel == nil or mylevel == 0 then
    res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264","gmcpval","char.status")
         luastmt = "gmcpdata = " .. gmcparg
         assert (loadstring (luastmt or "")) ()
         mylevel = tonumber(gmcpdata.level)
    end 
    --DebugNote('source room is : '..src)
    --DebugNote('source room type is : '..type(src))
    --DebugNote('destination room is : '..dst)
    --DebugNote('destination room type is : '..type(dst))
    if not rooms[src] or src == '-1' or stc == -1 then
        if src == "-1" or src == -1 then
            src = strip_colours("nomap_"..currentRoom.name.."_"..currentRoom.areaid)
            --DebugNote(strip_colours(src))
        end
        rooms[src] = load_room_from_database(src)
    end
    if not rooms[src] then
        return
    end
    if tostring(src) == tostring(dst) then
        return {}, 0
    end
    local walk_one = nil
    for dir, touid in pairs(rooms[src].exits) do
        if tostring(touid) == tostring(dst) and tonumber(rooms[src].exit_locks[dir]) <= mylevel and ((walk_one == nil) or (#dir > #walk_one)) then
            walk_one = dir -- if one room away, walk there (don't portal), but prefer a cexit
        end
    end
    if walk_one ~= nil then
        return {{dir = walk_one, uid = touid}}, 1
    end
    local depth = 0
    local max_depth = 500
    local room_sets = {}
    local rooms_list = {}
    local found = false
    local ftd = {}
    local f = ""
    local next_room = 0
    if type(src) ~= "number" then
        src = string.match(src, "^(nomap_.+)$") or tonumber(src)
    end
    if type(dst) ~= "number" then
        dst = string.match(dst, "^(nomap_.+)$") or tonumber(dst)
    end
    if src == dst or src == nil or dst == nil then
        return {}
    end
    src = tostring(src)
    dst = tostring(dst)
    table.insert(rooms_list, fixsql(dst))
    local visited = ""
    while not found and depth < max_depth do
        depth = depth + 1
        if depth > 1 then
            ftd = room_sets[depth - 1] or {}
            rooms_list = {}
            for k, v in pairs(ftd) do
                --DebugNote(v)
                table.insert(rooms_list, fixsql(v.fromuid))
            end -- for from, to, dir
            -- DebugNote('=======')
        end -- if depth
        -- prune the search space
        if visited ~= "" then
            visited = visited..","..table.concat(rooms_list, ",")
        else
            if noportals then
                visited = visited..fixsql("*") .. ","
            end
            if norecalls then
                visited = visited..fixsql("**") .. ","
            end
            visited = visited..table.concat(rooms_list, ",")
        end
        
        -- get all exits to any room in the previous set
        local q = string.format ("select fromuid, touid, dir from exits where touid in (%s) and fromuid not in (%s) and ((fromuid not in ('*','**') and level <= %s) or (fromuid in ('*','**') and level <= %s)) order by length(dir) asc", table.concat(rooms_list, ","), visited, mylevel, mylevel + (mytier * 10))
        local dcount = 0
        --DebugNote(q)
        room_sets[depth] = {}
        -- DebugNote(q)
        -- DebugNote("printing rows from the query")
        for row in dbnrowsWRAPPER(q) do
            -- print('database was open')
            dcount = dcount + 1
            -- DebugNote(row)
            --DebugNote('================'.. tostring(depth))
            -- ordering by length(dir) ensures that custom exits (always longer than 1 char) get
            -- used preferentially to normal ones (1 char)
            room_sets[depth][row.fromuid] = {fromuid = row.fromuid, touid = row.touid, dir = row.dir}
            --DebugNote(row.fromuid)
            --DebugNote(f)
            if row.fromuid == "*" or (row.fromuid == "**" and f ~= "*" and f ~= src) or row.fromuid == src then
                f = row.fromuid
                found = true
                found_depth = depth
            end -- if src
        end -- for select
        -- DebugNote("rooms_list")
        -- DebugNote(rooms_list)
        -- DebugNote("room_sets")
        -- DebugNote(room_sets)
        -- DebugNote("found_depth")
        -- DebugNote(found_depth)
        if dcount == 0 then
            return -- there is no path from here to there
        end -- if dcount
    end -- while
    if found == false then
        return
    end
    -- We've gotten back to the starting room from our destination. Now reconstruct the path.
    local path = {}
    -- set ftd to the first from,to,dir set where from was either our start room or * or **
    ftd = room_sets[found_depth][f]
    --DebugNote(room_sets[found_depth][f])
    if (f == "*" and rooms[src].noportal == 1) or (f == "**" and rooms[src].norecall == 1) then
        if rooms[src].norecall ~= 1 and bounce_recall ~= nil then
            table.insert(path, bounce_recall)
            if dst == bounce_recall.uid then
                return path, found_depth
            end
        elseif rooms[src].noportal ~= 1 and bounce_portal ~= nil then
            table.insert(path, bounce_portal)
            if dst == bounce_portal.uid then
                return path, found_depth
            end
        else
            local jump_room, path_type = findNearestJumpRoom(src, dst, f)
            if not jump_room then
                return
            end
            local path, first_depth = findpath(src, jump_room, true, true) -- this could be optimized away by building the path in findNearestJumpRoom, but the gain would be negligible
            if bit.band(path_type, 1) ~= 0 then
                -- path_type 1 means just walk to the destination
                return path, first_depth
            else
                local second_path, second_depth = findpath(jump_room, dst)
                for i, v in ipairs(second_path) do
                    table.insert(path, v) -- bug on this line if path is nil?
                end
                return path, first_depth + second_depth
            end
        end
    end
    table.insert(path, {dir = ftd.dir, uid = ftd.touid})
    next_room = ftd.touid
    while depth > 1 do
        depth = depth - 1
        ftd = room_sets[depth][next_room]
        next_room = ftd.touid
        -- this caching is probably not noticeably useful, so disable it for now
        --      if not rooms[ftd.touid] then -- if not in memory yet, get it
        --         rooms[ftd.touid] = load_room_from_database (ftd.touid)
        --      end
        table.insert(path, {dir = ftd.dir, uid = ftd.touid})
    end -- while
    return path, found_depth
end -- function findpath
-- end section of Fienish's work

function GOTO(roomId)
    if currentRoom == nil or currentRoom == {} then
        res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "room.info")
        luastmt = "gmcpdata = " .. gmcparg
        assert (loadstring (luastmt or "")) ()
        currentRoom = {
            name = gmcpdata.name,
            roomid = gmcpdata.num,
            areaid = gmcpdata.zone
        }
    end
    local path, dist = findpath(currentRoom.roomid, roomId)
    DebugNote(path)
    local speedwalk = ''
    if dist == nil then
        Note('There was no usable path to the creature.')
        return 0
    end
    wait.make (function()
        for i, p in pairs(path) do
            -- DebugNote(string.len(p['dir']))
            if string.len(p['dir']) > 1 then
                if string.len(speedwalk) > 0 then
                    DebugNote('speedwalk '..speedwalk)
                    Execute('run ' .. speedwalk)
                    speedwalk = ''
                end
                DebugNote('execute special')
                IS_WM_ENABLED = false
                local partial_cexit_command = p['dir']
                local strbegin, strend = string.find(partial_cexit_command, ";?wait%(%d*.?%d+%);?")
                while strbegin do
                    strbegin, strend = string.find(partial_cexit_command, ";?wait%(%d*.?%d+%);?")
                    if strbegin ~= nil and strbegin ~= 1 then
                        Execute(string.sub(partial_cexit_command, 1, strbegin - 1))
                    end
                    if strend then
                        local wait_time = tonumber(string.match(string.sub(partial_cexit_command, strbegin, strend), "wait%((%d*.?%d+)%)"))
                        SendNoEcho("echo {mapper_wait}wait("..wait_time..")")
                        line, wildcards = wait.regexp("^\\{mapper_wait\\}wait\\(([0-9]*\\.?[0-9]+)\\)", nil,trigger_flag.OmitFromOutput)
                        Note("CEXIT WAIT: waiting for "..wait_time.." seconds before continuing.")
                        wait.time(wait_time)
                        partial_cexit_command = string.sub(partial_cexit_command, strend + 1)
                    end
                end
                Execute(partial_cexit_command)
                IS_WM_ENABLED = true
                --Execute(p['dir'])
            else
                speedwalk = speedwalk .. p['dir']
            end
        end
        DebugNote('speedwalk2 ' ..speedwalk)
        if string.len(speedwalk)> 0 then
            Execute('run ' .. speedwalk)
        end
        SendNoEcho("echo {where restart}")
    end)
    --DebugNote('speedwalk2 ' ..speedwalk)
    --Execute('run ' .. speedwalk)
    --Execute('echo {end speedwalk}')
    return 1
end
