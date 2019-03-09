dofile (GetPluginInfo (GetPluginID (), 20) .. "luapath.lua")

require "tprint"
require "KillTable"
require "pluginhelper"
require "serialize"
require "socket"
require "DistCalc"
require "MovementFuncs"
require "LookupFunc"
require "AreaTableBuilder"
require "DBUtils"
require "gmcphelper"
ThreadHolder = coroutine.running()
counter = tonumber(1)
counter1 = tonumber(1)

local Debug = false
currentRoom = {}
local char_status
local currentState
local tableNumHolder
local charname
local GQ_flag = false
local GQ_num
local started = false
local CQuestHandler = require "questhandle"
local questHandler = CQuestHandler.create()
mylevel = 0
mytier = 0
mobsleft = {}
cp_mobs = {}
local qmob

timestart = 0
timeend = 0
auto_hunt_mob = ""

-- PageSize code
page_size = 0
kill_pagesize = 0
function Note(stuff)
    if stuff == nil then
        ColourNote("magenta", "black", "")
    else
        ColourNote("magenta", "black", tostring(stuff))
    end
end
function GetPageSize()
    kill_pagesize = 0
    EnableTriggerGroup("page_size", 1)
    SendNoEcho("pagesize")
end

function ResetPageSize()
    if page_size ~= 0 then
        SendNoEcho("pagesize " .. page_size)
    end
end
dir_map = {
    south = "s",
    north = "n",
    east  = "e",
    west  = "w",
    up    = "u",
    down  = "d"
}
function auto_hunt_start(name, line, wildcards)
    hunt_off()
    auto_hunt_stop()
    kill_scan_run()
    BroadcastPlugin(2,"Starting autohunt")
    EnableTrigger('auto_hunt', 1)
    EnableTrigger('kill_auto_hunt', 1)
    auto_hunt_mob = wildcards[1]
    SendNoEcho('hunt ' .. auto_hunt_mob)
    
end

function auto_hunt_continue(name, line, wildcards)
    local move = ""
    for i, p in pairs(wildcards) do
        DebugNote(p)
        DebugNote("i = "..i)
        if p ~= "" and i > 0 then
            move = wildcards[i + 1]
            DebugNote(move)
            break
        end
    end
    --if string.find(move, 'through') then
        if currentRoom ~= nil then
            query = string.format("select dir, fromuid, touid from exits where fromuid = %s and dir = '%s' order by length(dir) desc",
                currentRoom.roomid, dir_map[move])
            move1 = db_query(dbA, query)
            DebugNote(move1)
            if #move1 > 0 and move1[1].touid ~= "-1" then
                local to_room = move1[1].touid
                DebugNote("to_room : ".. to_room)
                query = string.format("select dir, fromuid, touid from exits where fromuid = %s and touid = %s order by length(dir) desc",
                    currentRoom.roomid, to_room)
                move1 = db_query(dbA, query)
                DebugNote('printing move table return:')
                DebugNote(move1)
                if #move1 > 0 then
                    move1 = move1[1]["dir"]
                else
                    Note(string.format('There was no link between $s and %s. Shutting Off', currentRoom.name, to_room))
                    return
                end
            else
                DebugNote(string.format('Looks like there is no mapper exit from %s heading %s. Falling back to direction', currentRoom.name, move))
                DebugNote(move)
                move1 = move
            end
        end
    --end
    if string.len(move1) == 1 and dir_map[move] ~= move1 then
        DebugNote(move)
        Execute(move)
    else
        DebugNote(move1)
        Execute(move1)
    end
    SendNoEcho('hunt '..auto_hunt_mob)
end

function auto_hunt_stop()
    EnableTrigger("auto_hunt", 0)
    EnableTrigger("kill_auto_hunt", 0)
end

function hunt_off()
    BroadcastPlugin(2,"Shutting huntings scripts off.")
    EnableTriggerGroup("HUNTING", false)
    kill_scan_run()
end

function getmemoryusage()
    collectgarbage('collect')
    return collectgarbage('count')
end

-- Converts single digit numbers to have a leading zero (as string)
function lz(int)
    num = tostring(int)
    if #num == 1 then num = "0" .. num end
    return num
end

-- Changes a float to a 2 digit integer (returned as a string) [Expects 0.xxxxxxxx]
function d2i(dec)
    return tostring(math.floor(dec * 100))
end

-- Converts a float (secs.millisecs) to a string of the format: hh:mm:ss.ms
function timetostr(floattime)
    secs = floattime
    hours = 0
    mins = 0
    dec = 0
    
    if secs >= 3600 then
        hours = math.floor(secs / 3600)
        secs = secs - (hours * 3600)
    end
    if secs >= 60 then
        mins = math.floor(secs / 60)
        secs = secs - (mins * 60)
    end
    dec = d2i(secs - math.floor(secs))
    secs = math.floor(secs)
    return tostring(lz(hours) .. ":" .. lz(mins) .. ":" .. lz(secs) .. "." .. dec)
end

function timeStart()
    timestart = socket.gettime()
end

function timeEnd()
    timeend = socket.gettime()
    Note ('Completion Time: '..timetostr(timeend - timestart))
end

function quickScan()
    Execute("scan " .. mobname)
end

function Toggle_Debug(name, line, wildcards)
    if string.find(line, "on") then
        Note ("Turning Debugging on")
        Debug = true
    else
        Note ("Turning Debugging off")
        Debug = false
    end
end

function cp_check(name, line, wildcards)
    if not didonce then
        Send('look')
    end
    Send('cp check')
    EnableTrigger('camp_item_start', 1)
    EnableTrigger("campaign_item", true)
    mobsleft = {}
    BroadcastPlugin(2, 'update level')
end

function gq_check(name, line, wildcards)
    DebugNote("gq_check")
    DebugNote(wildcards)
    GQ_flag = true
    EnableTrigger('camp_item_start', 1)
    DebugNote("GQ_flag set to "..tostring(GQ_flag))
    if wildcards ~= nil and tonumber(GQ_num) == tonumber(wildcards.num) then
        EnableTrigger("campaign_item", true)
        DebugNote("Gquest started")
        GQ_num = tonumber(wildcards[1])
        DebugNote (GQ_num)
        Send("gq ch")
        mobsleft = {}
        
    elseif #wildcards <= 1 then
        EnableTrigger("campaign_item", true)
        Send("gq ch")
        mobsleft = {}
    elseif tonumber(wildcards.num) ~= tonumber(GQ_num) then
        GQ_flag = false
        DebugNote("Shutting GQ_flag off")
        EnableTrigger('camp_item_start', 0)
    end
end

function gq_start(name, line, wildcards)
    DebugNote ("gq_start")
    GQ_num = tonumber(wildcards[1])
    DebugNote (GQ_num)
    GQ_flag = true
    DebugNote("GQ_flag set to "..tostring(GQ_flag))
    mobsleft = {}
end

function cpgq_quit(name, line, wildcards)
    DebugNote(name)
    DebugNote(line)
    DebugNote(wildcards)
    if wildcards[1] == "gq" then
        GQ_flag = false
        DebugNote("GQ_flag set to "..tostring(GQ_flag))
    end
    DebugNote("cpgq_quit")
    BroadcastPlugin(4)
    cp_mobs = {}
    clearTable()
end

function gq_end(name, line, wildcards)
    DebugNote(wildcards)
    BroadcastPlugin(4)
    if GQ_flag == false then return end
    if wildcards[1] == GQ_num then
        DebugNote("if block")
        GQ_flag = false
        DebugNote("GQ_flag set to "..tostring(GQ_flag))
        cp_mobs = {}
        clearTable()
    elseif #wildcards < 1 then
        DebugNote("elseif block")
        GQ_flag = false
        DebugNote("GQ_flag set to "..tostring(GQ_flag))
    end
    DebugNote ("Gq is off now")
end

function add_Keywords(name, line, wildcards)
    if check_CPMobs_Table() < 1 then
        Note ("you don't have CPMobs table, you can't use this function, try installing the CPMobs plugin")
        return
    end
    query = string.format("UPDATE CPMobs SET keywords=%s WHERE name=%s;", fixsql(wildcards[2]), fixsql(wildcards[1]))
    querycheck = string.format("Select count(1) as count from CPMobs where name= %s;", fixsql(wildcards[1]))
    count = db_query(dbkt, querycheck)
    count = count[1].count
    if count < 1 then
        Note ("You have the name wrong, or it is not in the table, try again!")
        Note ("You entered: " .. wildcards[1])
    end
    if tonumber(count) < 1 then
        return
    end
    db_exec(dbkt, query)
    
    Note ("Added " .. wildcards[2] .. " to the mob entry for " .. wildcards[1])
end

function check_CPMobs_Table()
    local count = 0
    local checktable = "SELECT Count(1) as count FROM sqlite_master WHERE type='table' AND name='CPMobs';"
    count = db_query(dbkt, checktable)
    count = count[1].count
    if count < 1 then
        return 0
    end
    return 1
end

function camp_item_start()-- get your campaign items
    clearTable()
    
    EnableTrigger('campaign_item', false)
    EnableTrigger('camp_item_start', 0)
    cp_mobs = {}
    cp_mobs = mobsleft
    
    -- This is the first call to buildToomTable()
    buildRoomTable()
    
    FirstRun_cp_var = false
    check_dead()
    DebugNote(collectgarbage("count") * 1024)
    collectgarbage("collect")
    DebugNote(collectgarbage("count") * 1024)
    
end

function campaign_item (name, line, wildcards)-- the actual campaign item getter
    DebugNote("start cp_item mobsleft")
    DebugNote (wildcards)
    DebugNote("end cp_item mobsleft")
    name = wildcards.name
    mobdead = false
    location = wildcards.location
    num = tonumber(wildcards.num)
    if wildcards.dead == ' - Dead' then
        mobdead = true
    else
        mobdead = false
    end
    
    if not name or not location then
        Note("error parsing line: ", line)
    else
        table.insert(mobsleft, {name = name, location = location, mobdead = mobdead, mobdead = mobdead, false, num = tonumber(num)})
    end
end

function delete_mob_from_table()
    local found = false
    local tmp = {}
    local num
    if AutoUpdate_var == false and last_Enemy ~= nil then
        for p, q in pairs (room_num_table) do
            num = tonumber(q[6]) or 1
            DebugNote (q)
            DebugNote(q[6])
            DebugNote ("Number of kills needed at time of delete_mob_from_table "..num)
            if string.lower(last_Enemy) == string.lower(q[2]) and num == 1 then
                table.remove(room_num_table, p)
                table.remove(cp_mobs, p)
                found = true
                break
            elseif string.lower(last_Enemy) == string.lower(q[2]) then
                q[6] = q[6] - 1
                cp_mobs[p].num = cp_mobs[p].num - 1
                DebugNote(cp_mobs)
                DebugNote(cp_mobs[p][q])
                DebugNote ("number of mobs is " .. q[6])
                found = true
                break
            end
        end
        for p, q in pairs (room_num_table2) do
            if string.lower(last_Enemy) == string.lower(q[2]) then
                room_num_table2[p] = nil
            else
                table.insert(tmp, room_num_table2[p])
            end
        end
        room_num_table2 = tmp
        if found == false then
            DebugNote("Begin cp_mobs[mob_next_delete_value] check")
            DebugNote(num)
            DebugNote("End cp_mobs[mob_next_delete_value] check")
            table.remove(room_num_table, mob_next_delete_value)
            table.remove(cp_mobs, mob_next_delete_value)
            DebugNote(GQ_flag)
            if GQ_flag == true then
                do_Execute_no_echo("gq check")
            else
                do_Execute_no_echo("cp check")
            end
        end
        mob_index = 1
    end
    check_diff()
    sortRoomCPByPath()
    var.cp_mobs = serialize.save("cp_mobs", cp_mobs)
    BroadcastPlugin(1, var.cp_mobs)
    DebugNote(collectgarbage("count") * 1024)
    collectgarbage("collect")
    DebugNote(collectgarbage("count") * 1024)
end

function delete_mob_from_table_index(val)
    if val > #room_num_table then
        return
    end 
    if AutoUpdate_var == false and last_Enemy ~= nil then
        for p, q in pairs (room_num_table2) do
            num = tonumber(q[6]) or 1
            if string.lower(last_Enemy) == string.lower(q[2]) then
                table.remove(room_num_table2, p)
            end
        end
        DebugNote('val: ' .. val)
        DebugNote(room_num_table[val])
        DebugNote(room_num_table)
        if room_num_table[val].num == 1 then
            table.remove(room_num_table, tonumber(val))
        else
            room_num_table[val][6] = room_num_table[val][6] - 1
            cp_mobs[val].num = cp_mobs[val].num - 1
        end
        DebugNote(collectgarbage("count") * 1024)
        collectgarbage("collect")
        DebugNote(collectgarbage("count") * 1024)
        mob_index = 1
        check_diff()
    end
end

function CPFound()
    if tonumber(count) > 0 then
        Execute ("wm " .. count .. "." ..mobname)
    else
        Execute ("wm " ..mobname)
    end
    EnableTriggerGroup("HUNTING", false)
end

function not_here_script()
    Execute("wm "..mobname)
    Note ("THIS IS NOT THE CORRECT AREA OR THE MOB IS DEAD")
    EnableTriggerGroup("HUNTING", false)
    
end

function quest_color()
    ColourNote ("white", "blue", "==================QUEST MOB HERE!!!!!!!!!!!!!!!!!!!!!!!=================")
end

function cpn_script (index, line, wildcards)
    hunt_off()
    kill_scan_run()
    local numcheck
    
    if wildcards ~= nil then
        numcheck = tonumber(wildcards[1])
    end
    
    DebugNote (index)
    DebugNote (type(index))
    DebugNote (numcheck)
    if index ~= nil and type(index) == 'string' then
        if #wildcards < 1 then
            index = mob_index
        elseif #wildcards <= 1 and numcheck == nil then
            EnableTriggerGroup("HUNTING", true)
            reset_counter()
            mobname = wildcards[1]
            Execute ("hunt " .. mobname)
            return
        end
        if wildcards[1] == nil and mob_index ~= nil then
        else
            index = wildcards[1]
        end
    end
    index = tonumber(index)
    if room_num_table[index] == nil then
        Note ("No cp_mob at that value")
        return
    end
    EnableTriggerGroup("HUNTING", true)
    reset_counter()
    if room_num_table[index][1] ~= nil and cpn_is_room_type == false then
        getTable(index)
        Execute ("hunt " .. mobname)
    else
        Note("Either not on a cp or haven't checked it yet, or its a room type cp. Use hyperlink.")
        cpn_is_room_type = false
        EnableTriggerGroup("HUNTING", false)
    end
end

AutoUpdate_var = false
greedy = false
FirstRun_cp_var = true

-- This function is just for testing. It should never actually be used.
function printVars()
   -- print(#area_table)
    Debug = true
    -- tprint(findpath(currentRoom.roomid, 29839))
    --   mobsleft = {}
    --   EnableTrigger('campaign_item',1)
    --   EnableTrigger('camp_item_start',1)
    Execute("echo You still have to kill * a delightful oil painting (West wing)")
Execute("echo You still have to kill * an armored warhorse (Horse pasture)")
Execute("echo You still have to kill * a hurrying Illorian (On the way to the Tournament)")
Execute("echo You still have to kill * an oil painting (West wing)")
Execute("echo You still have to kill * The Djinn (Playground)")
Execute("echo You still have to kill * an alchemist (The Grand Square)")
Execute("echo You still have to kill * a tapestry (Grand staircase)")
Execute("echo You still have to kill * an amazon female (Inside the dining room)")
Execute("echo You still have to kill * an elven warrior (The Lightstone)")
Execute("echo You still have to kill * Jurn the Barbarian (In the Alehouse)")
Execute("echo You still have to kill * a maid (Dining room)")
Execute("echo You still have to kill * an orc slave (Deeper in the Mine)")
Execute("echo You still have to kill * Davven (Kitchen)")
    -- Execute("echo You still have to kill * some burning embers (Scorched earth)")
    -- Execute("echo You still have to kill * the stage manager (Rehearsal Room B)")
    -- Execute("echo You still have to kill * a servant (Western Tower)")
    -- Execute("echo You still have to kill * a cavorting faerie (The Botanical Gardens)")
    -- Execute("echo You still have to kill * a blacksmith (A blacksmith's shop)")
    -- Execute("echo You still have to kill * a partially clothed actor (Offstage:No Park Guest Access)")
    -- Execute("echo You still have to kill * Al-E-Gator (Swamped!)")
    -- Execute("echo You still have to kill * a citizen of the realm (A Path Around the Maw)")
    -- Execute("echo You still have to kill * a citizen (Main street)")
    -- Execute("echo You still have to kill * a dolphinfish (Exploring the Deep Ocean)")
    -- Execute("echo You still have to kill * a brilliant Nyarlithit (The Final Conflict)")
    -- Execute("echo You still have to kill * Good Eclaboussure (Outer Space)")
    -- Execute("echo You still have to kill * the ice lord (The Chamber of the Ice Lord)")
    -- Execute("echo You still have to kill * a raw recruit (An Iron Training Room)")
    -- Execute("echo You still have to kill * a guest (A Guest Chamber)")
    -- Execute("echo You still have to kill * a killer bee (A Wilting Root Hair)")
    -- Execute("echo You still have to kill * Evil Peane (Outer Space)")
    -- Execute("echo You still have to kill * a Reakle (Inside the Great Hall of the Castle)")
    -- Execute("echo You still have to kill 1 * a large rat (Western Side of the Balcony)")
    -- Execute("echo You still have to kill 1 * Moriarty Jones (In Moriarty's Room)")
    -- Execute("echo You still have to kill 1 * Leon Birdie (Prosper's Island)")
    -- Execute("echo You still have to kill 1 * a worshipper of the sacred flame (The room of purification)")
    -- Execute("echo You still have to kill 2 * a line cook (The kitchens)")
    -- Execute("echo You still have to kill 2 * a blood beast (The Blood Swamp)")
    -- Execute("echo You still have to kill 1 * Vulcris (Vulcris' Sanctum)")
    -- Execute("echo You still have to kill 1 * Johna (The Partroxis)")
    -- Execute("echo You still have to kill 2 * a smiling faerie (The Botanical Gardens)")
    -- Execute("echo You still have to kill 2 * a cavorting faerie (The Botanical Gardens)")
    -- Execute("echo Note: One or more target names in this gquest might be slightly scrambled.")
    --check_area_table()
    Debug =false
    tprint(t_lookup_preloaded)
    mobbuf = {}
    if t_lookup_preloaded ~= nil and t_lookup_preloaded[1] ~= nil  then
        Note('Try ah on one of these mobs as they are in the same room...')
        if t_lookup_preloaded[2] ~= nil then
            mobbuf = lookup('','',{'room ' .. t_lookup_preloaded[1] .. ' area '.. t_lookup_preloaded[2]})
        else
            mobbuf = lookup('','',{'room ' .. t_lookup_preloaded[1]})
        end
    else
        Note('Nothing was loaded, try wm <mob> first.')
    end
    tprint(mobbuf)
end
-- end testing function
kill_info = {}
-- I hate to do it this way and will come up with a better solution... but for now
damage_verbs = {
    ' misses ',
    ' tickles ',
    ' bruises ',
    ' scratches ',
    ' grazes ',
    ' nicks ',
    ' blasts',
    ' scars ',
    ' hits ',
    ' injures ',
    ' wounds ',
    ' mauls ',
    ' maims ',
    ' mangles ',
    ' mars ',
    ' massacres ',
    ' dismembers ',
    ' devastates ',
    ' disembowels ',
    ' lacerates ',
    ' LACERATES ',
    ' DECIMATES ',
    ' DEVASTATES ',
    ' ERADICATES ',
    ' OBLITERATES ',
    ' EXTIRPATES ',
    ' INCINERATES ',
    ' MUTILATES ',
    ' DISEMBOWELS ',
    ' MASSACRES ',
    ' DISMEMBERS ',
    ' RENDS ',
    ' meteorites ',
    ' glaciates ',
    ' nukes ',
    ' implodes ',
    ' asphyxiates ', --
    ' liquidates ', --
    ' fissures ', --
    ' exterminates ', --
    ' ravages ', --
    ' atomizes ', --
    ' sunders ', --
    ' tears into ', --
    ' destroys ', --
    ' pulverizes ', --
    ' demolishes ', --
    ' mutilates ', --
    ' incinerates ', --
    ' extirpates ', --
    ' obliterates ', --
    ' eradicates ', --
    ' annihilates ', -- nnih%
    ' evaporates ', -- vapor%
    ' ruptures ', -- upt%
    ' shatters ', -- hatter%
    ' slaughters ', -- laughters%
    ' vaporizes ', --vapor%
    ' wastes ', -- astes%
    ' shreds ',
    ' cremates ', -- remat%
    ' supernovas ',
    ' The charge slams into ',
    ' does UNSPEAKABLE things to ',
    ' does UNTHINKABLE things to ',
    ' does UNIMAGINABLE things to ',
    ' does UNBELIEVABLE things to ',
    ' %- BLASTS %- ',
    ' %-= DEMOLISHES =%- ',
    ' %*%* SHREDS %*%* ',
    ' %*%*%*%* DESTROYS %*%*%*%* ',
    ' %*%*%*%*%* PULVERIZES %*%*%*%*%* ',
    ' %-=%- VAPORIZES %-=%- ',
    ' <%-==%-> ATOMIZES <%-==%-> ',
    ' <%-:%-> ASPHYXIATES <%-:%-> ',
    ' <%-%*%-> RAVAGES <%-%*%-> ',
    ' <>%*<> FISSURES <>%*<> ',
    ' <%*><%*> LIQUIDATES <%*><%*> ',
    ' <%*><%*><%*> EVAPORATES <%*><%*><%*> ',
    ' <%-=%-> SUNDERS <%-=%-> ',
    ' <=%-=><=%-=> TEARS INTO <=%-=><=%-=> ',
    ' <%->%*<=> WASTES <=>%*<%-> ',
    ' <%-%+%-><%-%*%-> CREMATES <%-%*%-><%-%+%-> ',
    ' <%*><%*><%*><%*> ANNIHILATES <%*><%*><%*><%*> ',
    ' <%-%-%*%-%-><%-%-%*%-%-> IMPLODES <%-%-%*%-%-><%-%-%*%-%-> ',
    ' <%-><%-=%-><%-> EXTERMINATES <%-><%-=%-><%-> ',
    ' <%-==%-><%-==%-> SHATTERS <%-==%-><%-==%-> ',
    ' <%*><%-:%-><%*> SLAUGHTERS <%*><%-:%-><%*> ',
    ' <%-%*%-><%-><%-%*%-> RUPTURES <%-%*%-><%-><%-%*%-> ',
    ' <%-%*%-><%*><%-%*%-> NUKES <%-%*%-><%*><%-%*%-> ',
    ' %-<%[=%-%+%-=%]<:::<>:::> GLACIATES <:::<>:::>%[=%-%+%-=%]>%- ',
    ' <%-=%-><%-:%-%*%-:%-><%*%-%-%*> METEORITES <%*%-%-%*><%-:%-%*%-:%-><%-=%-> ',
    ' <%-:%-><%-:%-%*%-:%-><%-%*%-> SUPERNOVAS <%-%*%-><%-:%-%*%-:%-><%-:%-> ',
}

function check_cur_mob(test_table)
    if not enemy then
        enemy = ""
    end
    cur_mob = nil
    
    if #test_table == 3 then
        local line = test_table[1][1]
        DebugNote('printing test table: '..test_table[1][1])
        
        if string.find(line, "%!") ~= nil then
            temp = string.sub(line, 8, string.find(line, "%!") - 1)
        elseif string.find(line, "%.") then
            temp = string.sub(line, 8, string.find(line, "%.") - 1)
        end
        
        for i, v in pairs(damage_verbs) do
            o, p = string.find(temp, v)
            if p ~= nil then
                temp = string.sub(temp, p + 1, #temp)
                
                return temp
            end
        end
        
        i = string.find(temp, "%A")
        while i do
            temp = string.sub(temp, i + 1, #temp)
            i = string.find(temp, "[%A][%s]")
        end
        
        temp = string.sub(temp, 2, #temp)
        return temp
    end
    
    for i, p in pairs(test_table) do
        test_color = string.sub(p[1], -2, -2)
        if i > 1 and p[2] == test_table[1][2] and (test_color == '!' or test_color == '.') then
            cur_mob = string.sub(p[1], 0, -3)
            if cur_mob ~= enemy and cur_mob ~= 'Someone' then
                ret = cur_mob
            elseif enemy ~= current_enemy_gbl then
                ret = enemy
            end
        end
    end
    
    if cur_mob == nil and enemy ~= nil then
        ret = enemy
    end
    return ret
end

function mob_name(name, line, wildcards, styles)
    local test_table = {}
    for i, p in pairs(styles) do
        table.insert(test_table, {
            p.text,
            RGBColourToName(p.textcolour),
        RGBColourToName(p.backcolour)})
    end
    last_Enemy = check_cur_mob(test_table)
end

function Add_To_Kill_Table(name, line, wildcards)
    if greedy == false then
        return
    end
    kill_info.room_id = currentRoom.roomid
    kill_info.name = last_Enemy
    Add_Kill_Table(kill_info)
    DebugNote(kill_info)
end

function check_dead ()
    check_diff()
    for p, q in ipairs(room_num_table) do
        if cp_mobs[p].mobdead ~= nil then
            if q[2] == cp_mobs[p].name and cp_mobs[p].mobdead == true then --used to be k.name and k.mobdead in case it doesn't work
                room_num_table[p][3] = true
            else
                room_num_table[p][3] = false
            end
        end
    end
end

-- TODO: Evaluate if this function is actually needed anymore.
function check_diff()
    
    if AutoUpdate_var == true then
        return
    end
    
    for p, q in pairs(room_num_table) do
        
        if cp_mobs[p] == nil then
            delete_mob_from_table_index(p)
            return
        end
        
        if string.lower(q[2]) ~= string.lower(cp_mobs[p].name) and #room_num_table > #cp_mobs then
            delete_mob_from_table_index(p) -- not sure if this is working yet
            DebugNote ("If you see this message this was the function causing the stack overflow")
        elseif string.lower(q[2]) ~= string.lower(cp_mobs[p].name) and #room_num_table < #cp_mobs then
            DebugNote('room <cp_mobs and names dont match')
            buildRoomTable()
            return
        end
        
        if string.lower(q[2]) ~= string.lower(cp_mobs[p].name) and #room_num_table == #cp_mobs then
            DebugNote('room ==cp_mobs and names dont match')
            DebugNote(q[2] .. " " .. cp_mobs[p].name)
            buildRoomTable()
        end
    end
    mob_index = 1
    var.cp_mobs = serialize.save("cp_mobs", cp_mobs)
    BroadcastPlugin(1, var.cp_mobs)
end

myThread = nil
local level = 0
local oldlevel = 0
-- New initialization checks - Kobus
got_room = false
got_char = false
didonce = false

CPMobsLevelBound = nil
-- takes a level and makes a CPmobs table that is within 30 level of our current level
function CpMobsAbr(str)
    CPMobsLevelBound = nil
    levelAdj = 30
    levmin = tonumber(str) - levelAdj
    
    if levmin < 0 then levmin = 0 end
    
    levmax = tonumber(str) + levelAdj
    query = string.format("select * from CPMobs " ..
        " where level between %s and %s " ..
    "  order by  name, timeskilled desc", levmin, levmax)
    
    c = 0
    CPMobsLevelBound = db_query(dbkt, query)
    oldlevel = mylevel -- Won't rebuild until we level again - Kobus
end

room_num_table = {}

function clearTable()
    room_num_table = {}
    room_num_table2 = {}
end

function makeTable(room_num, name, bool, isInTable, area, num, roomName, rooms_found)-- stores all names and room numbers into a global table
    room_num_table[counter] = {room_num, name, bool, isInTable, area, tonumber(num), roomName, rooms_found}
    counter = counter + 1
    -- tprint(room_num_table)
    -- print(counter)
    
end
function makeTable2(room_num, name, bool, inTable, area)-- stores all names and room numbers into a global table
    room_num_table2[counter1] = {room_num, name, bool, inTable, area}
    counter1 = counter1 + 1
    
end
--TODO: Change both prints to actually be something worth looking at.
function printTable() -- prints the global table for names and room numbers, used for debugging or quick checking
    if room_num_table ~= nil and #room_num_table > 0 then
        ColourNote("Gray", "", "NUM  Mob name                             Dist   RoomId        Area")
        ColourNote("Gray", "", "------------------------------------------------------------------------");
        for i, row in pairs(cp_mobs) do
            
            Note(string.format("%3d  %-35s  %-3s %-10s (%s) ", i, row.name, row.dist, room_num_table[i][1], row.location))
        end
        ColourNote("Gray", "", "------------------------------------------------------------------------");
        DebugNote(cp_mobs)
    else
        Note ("Nothing to print")
    end
end

function printTable1() -- prints the global table for names and room numbers, used for debugging or quick checking
    if room_num_table2 ~= nil and #room_num_table2 > 0 then
        tprint(room_num_table2)
    else
        Note ("Nothing to print")
    end
end

curMob = ''
mobname = ''
word_count = tonumber(0)

function getTable(index) -- returns the first item in the table of room numbers, also makes a variable 'mobname' which is used for the autokill comand
    if room_num_table[index] == nil then
        return - 1
    end
    local num = room_num_table[tonumber(index)][1]
    curMob = room_num_table[tonumber(index)][2]
    getName(index, 1)
    return num, room_num_table[tonumber(index)]
end
-- Questioning why I am passing the num variable here... was this legacy?
function getName(index, num)
    local s = ''
    if cp_mobs == nil then
        Note ("Use tcp before that command please")
        return
    end
    s = room_num_table[tonumber(index)][2] or curMob
    mobname = sanitizeName(s)
end

function sanitizeName(s)
    local exit = 0
    if s == nil then
        Note("s was nil")
        return
    end
    if check_CPMobs_Table() > 0 then-- this needs to be reworked once all versions are unified. Aka when all versions have CPMobs support for Room CPs
        check_Keywords = string.format("SELECT keywords from CPMobs WHERE name= %s and keywords <> '';", fixsql(s))
        for _, keys in ipairs(db_query(dbkt, check_Keywords)) do
            DebugNote(keys)
            if keys.keywords ~= nil and keys.keywords ~= '' then
                return keys.keywords
            end
        end
    end
    local s2 = {}
    s = string.gsub(s, "-", " ")
    s = string.gsub(s, "'", " ")
    s = string.gsub(s, "%@r", " ")
    for i in s:gmatch("%a+") do
        word_count = tonumber(word_count) + 1
        s2[word_count] = i
        s2[word_count] = string.gsub(s2[word_count], ",", " ")
    end
    word_count = 0
    if (s2[1] == "a" or s2[1] == "A" or s2[1] == "An" or s2[1] == "the" or s2[1] == "The" or s2[1] == "an") and table.getn(s2) > 1 then
        if table.getn(s2) > 2
            then
            s2[2] = string.sub(s2[2], 0, 3)
            s2[3] = string.sub(s2[#s2], 0, 3)
            mobname = s2[2] .. " "..s2[3]
        else
            mobname = s2[2]
        end
    else
        if table.getn(s2) > 1
            then
            s2[1] = string.sub(s2[1], 0, 3)
            s2[2] = string.sub(s2[#s2], 0, 3)
            mobname = s2[1] .. " "..s2[2]
        else
            mobname = s2[1]
        end
    end
    return mobname
end

function buildRoomTable()-- This sends the table to get room_ids
    --local time1 = socket.gettime()*1000
    if cp_mobs == nil then
        cp_mobs = mobsleft
    end
    counter = tonumber(1)
    counter1 = tonumber(1)
    FirstRun_cp_var = false
    clearTable()
    local roomCPCheck = 0
    for i, v in ipairs (cp_mobs) do
        DebugNote(cp_mobs[i].name)
        DebugNote(i)
        getRoomId(cp_mobs[i].name, i)
        DebugNote("room_num_table")
        DebugNote(room_num_table)
    end
    DebugNote("room_num_table")
    DebugNote(room_num_table)
    for i, v in ipairs(room_num_table) do
        if (room_num_table[i][4] == false) then
            cp_mobs[i].intable = false
        else
            cp_mobs[i].intable = true
        end
    end
    DebugNote('==============================')
    sortRoomCPByPath()
    var.cp_mobs = serialize.save("cp_mobs", cp_mobs)
    BroadcastPlugin(1, var.cp_mobs)
end

local shortaname

function getRoomId(name, tableNum)-- Gets a roomId from campaign
    local loc = cp_mobs[tableNum].location
    dbA = GetInfo (66) .. 'Aardwolf.db'
    
    local query1 = "select rooms.uid as room, rooms.name as roomName, rooms.area as area, areas.name as areaName, 'room' as type " ..
    " from rooms rooms, areas " ..
    " where areas.uid = rooms.area and " ..
    " rooms.name = %s " ..
    " union " ..
    " SELECT rooms.uid as room, rooms.name as roomName, areas.uid as area, areas.name as areaName, 'area' as type" ..
    " FROM areas, rooms " ..
    " WHERE areas.name = %s and " ..
    "rooms.area = areas.uid " ..
    " ORDER BY type ASC "
    sql_now = string.format(query1, fixsql(loc), fixsql(loc))
    
    local count_check = 0
    local hld = {}
    for _, rows in ipairs(db_query(dbA, sql_now)) do
        table.insert(hld, rows)
    end
    
    if #hld == 0 then
        print(loc)
        print('this cp will be weird because of unmapped rooms.. all entries are subject TOL has broken')
        makeTable(-1, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, false, cp_mobs[tableNum].location, cp_mobs[tableNum].num, '', 0)
        return
    end
    for g, rows in pairs(hld) do
        -- this whole thing needs reworked... its a mess right now..
        if rows.type == 'room' then
            getRoomIdRoomCP(name, name, tableNum)
            return
        else
            getRoomIdAreaCP(name, tableNum)
            return
        end
    end
    -- testing this to see if it fixes unmapped room issue
end

sublist = {1, 1}

function getRoomIdAreaCP(name, tableNum)
    local nameHolder = nil
    local roomNumber = nil
    local roomTemp = nil
    local loc = cp_mobs[tableNum].location
    local found = false
    local time1 = socket.gettime()
    local thisrooms = rooms_tbl
    local thisareas = areas_tbl
    local timeskilled = 0
    local cpmobquery = string.format("select  * " ..
        "from CPMobs " ..
        "where name like %s and " ..
        "area_name = %s " ..
    "ORDER by timeskilled desc ", fixsql(name), fixsql(loc))
    test_timeskileed = {}
    
    if CPMobsLevelBound ~= nil then
        for i, p in pairs(CPMobsLevelBound) do
            if name == p.name and loc == p.area_name and timeskilled < p.timeskilled then
                DebugNote(p)
                nameHolder = name
                roomNumber = p.room_id
                timeskilled = p.timeskilled
                found = true
                
            end
            if name == p.name and loc == p.area_name then
                table.insert(test_timeskileed, {p})
            end
        end
    end
    
    if found == false then
        DebugNote("in query block")
        for _, a in ipairs(db_query(dbkt, cpmobquery)) do
            DebugNote(a)
            if found == false then
                DebugNote('the one I will use is: ')
                DebugNote (a)
                nameHolder = a.name
                roomNumber = a.room_id
                found = true
                table.insert(test_timeskileed, {a})
            end
        end
    end
    
    local count = 0
    if found == false then
        sublist = {}
        for i, p in pairs(mobktbl) do
            if p.name == name then
                table.insert(sublist, {p.name, p.room_id, p.timeskilled})
            end
        end
        
        DebugNote("\n In second block " .. name.."\n")
        for i, a in pairs(sublist) do
            count = count + 1
            DebugNote(a)
            DebugNote("-----")
            DebugNote('found is ' .. tostring(found))
            nameHolder = a[1]
            roomTemp = tostring(a[2])
            if found == false then
                DebugNote(thisrooms[roomTemp])
                if thisrooms[roomTemp] ~= nil then
                    if loc == thisareas[thisrooms[roomTemp].area].name and found == false then
                        DebugNote(a[1])
                        found = true
                        roomNumber = roomTemp
                        table.insert(test_timeskileed, {a})
                    end
                    DebugNote("+++++")
                end
            end
        end
    end
    
    if roomNumber ~= nil and nameHolder ~= nil then
        DebugNote ("check")
        DebugNote(cp_mobs[tableNum].num)
        DebugNote ("///check")
        makeTable(tonumber(roomNumber), nameHolder, cp_mobs[tableNum].mobdead, true, loc, cp_mobs[tableNum].num, #test_timeskileed or 0)
        mob_index = 1
    end
    
    if roomNumber == nil then
        DebugNote("here")
        makeTable(loc, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, false, loc, cp_mobs[tableNum].num, #test_timeskileed or 0)
        mob_index = 1
    end
    
    DebugNote("Times killed table")
    DebugNote(test_timeskileed)
    DebugNote("Length of timeskilled")
    DebugNote(#test_timeskileed)
    DebugNote("Times killed table === end")
end

function getLengthOfTimesKileed(test_timeskilleed)
    if #test_timeskilleed == nil then 
        return 0
    else
        return #test_timeskilleed
    end
end

function getRoomIdRoomCP(name, nameHolder, tableNum)-- TODO some bug here where it drops the last 2 things in list
    local loc = cp_mobs[tableNum].location
    local mob_table_name = ''
    local rows_counter = 1
    local rows_counter_check = 0
    local make1 = makeTable
    local make2 = makeTable2
    local call = CallPlugin
    local DebugNote = DebugNote
    local findmob_table = {}
    local area_table = {}
    local strbld = string.format
    local room_num_table = room_num_table
    local room_num_table2 = room_num_table2
    local tableNum = tonumber(tableNum)
    local levelAdj = 11
    local found = 0
    local areaName
    local timeskilled = 0
    local roomNumber
    test_timeskileed = {}
    res, gmcparg = call("3e7dedbe37e44942dd46d264", "gmcpval", "char") --- We just want the gmcp.char section.
    luastmt = "gmcpdata = " .. gmcparg --- Convert the serialized string back into a lua table.
    assert (loadstring (luastmt or "")) ()
    level = tonumber(gmcpdata.status.level) -- uncomment for live
    --level = 201
    if GQ_flag then levelAdj = 22 end
    --level = 70 -- for testing
    min_level = level - levelAdj
    max_level = level + levelAdj
    if CPMobsLevelBound ~= nil then
        for i, p in pairs(CPMobsLevelBound) do
            if name == p.name and loc == p.room_name and timeskilled < p.timeskilled then
                roomNumber = p.room_id
                areaName = p.area_name
                timeskilled = p.timeskilled
            end
            if name == p.name and loc == p.room_name then
                table.insert(test_timeskileed, {p})
            end
        end
        if roomNumber ~= nil and areaName ~= nil then
            DebugNote("mob is  = "..name)
            DebugNote("timeskilled = "..timeskilled)
            make1(roomNumber, name, cp_mobs[tableNum].mobdead, true, areaName, cp_mobs[tableNum].num, #test_timeskileed or 0)

            DebugNote("Times killed table")
            DebugNote(test_timeskileed)
            DebugNote("Times killed table === end")
            return
        end
    end
    if (min_level < 0)then min_level = 0 end
    local queryCount = strbld("select COUNT(1) as counter" ..
        " from rooms, areas" ..
    " where areas.uid = rooms.area and rooms.name = %s", fixsql(cp_mobs[tableNum].location))
    local query1 = strbld("select rooms.uid as roomuid," ..
        " areas.name as areaName," ..
        " rooms.name as roomName, " ..
        " areas.uid as areauid " ..
        " from rooms rooms, areas " ..
    " where areas.uid = rooms.area and rooms.name = %s", fixsql(cp_mobs[tableNum].location))
    
    local cpmobquery = string.format("select *" ..
        "from CPMobs " ..
        "where name like %s and " ..
        "room_name = %s" ..
    "ORDER by timeskilled asc ", fixsql(name), fixsql(loc))
    
    for _, rows in ipairs(db_query(dbkt, cpmobquery)) do
        roomNumber = rows.room_id
        areaName = rows.area_name
        timeskilled = rows.timeskilled
        found = 1
        table.insert(test_timeskileed, {rows})
    end
    if found == 1 then
        found = 0
        DebugNote("found it in the cp_mobs table 001")
        DebugNote("mob is  = "..cp_mobs[tableNum].name)
        DebugNote("timeskilled = "..timeskilled)
        make1(roomNumber, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, true, areaName, cp_mobs[tableNum].num, #test_timeskileed or 0)
        DebugNote('roomNumber '..roomNumber)
        DebugNote('cp_mobs[tableNum].name '.. cp_mobs[tableNum].name)
        DebugNote('area_table[z].areaName '.. areaName)
        DebugNote('cp_mobs[tableNum].num '.. (cp_mobs[tableNum].num or 'nil'))
        DebugNote("Times killed table")
        DebugNote(test_timeskileed)
        DebugNote("Times killed table === end")
        return
    end
    for _, rows in ipairs(db_query(dbA, queryCount)) do
        rows_counter = rows.counter
    end
    for _, rows in ipairs(db_query(dbA, query1)) do
        rows_counter_check = rows_counter_check + 1
        area_table[rows_counter_check] = rows
    end
    local area_table_size = #area_table
    local area_level_size = 0
    for i, _ in pairs(areaLevel) do
        area_level_size = area_level_size + 1
    end
    if areaLevel == nil or area_level_size == 0 then
        Note('area table was nill when checking mobs, rebuilding...')
        areaLevel = db_query_area(dbkt, "select keyword, name, afrom, ato, alock from areas")
        Note('Done rebuilding, moving forward...')
    end
    for z = 1, area_table_size do
        roomNumber = tonumber(area_table[z].roomuid)
        DebugNote("area_level_size: " .. area_level_size)
        DebugNote("area_table size: " .. #area_table)
        DebugNote(area_table[z].areauid)
        if area_table[z].areauid == 'prosper' and level > 180 then
            DebugNote("prosper was found in the SH range setting things up")
            areaLevel[area_table[z].areauid].maxLevel = 201
            areaLevel[area_table[z].areauid].minLevel = 175
        end
        if area_table[z].areauid == 'sohtwo' and level > 180 then
            DebugNote("sowtwo found, setting things up")
            areaLevel[area_table[z].areauid] = {
                lock = 0,
                minLevel = 175,
                keyword = area_table[z].areauid,
                name = area_table[z].name,
                maxLevel = 201
            }
        end
        if areaLevel[area_table[z].areauid] == nil then
            DebugNote("Could not find an entry for " .. area_table[z].areauid)
            areaLevel[area_table[z].areauid] = {
                lock = 0,
                minLevel = 0,
                keyword = area_table[z].areauid,
                name = area_table[z].name,
                maxLevel = 0
            }
        end
        DebugNote(areaLevel[area_table[z].areauid])
        if areaLevel[area_table[z].areauid].minLevel > max_level or areaLevel[area_table[z].areauid].maxLevel < min_level then
            rows_counter = rows_counter - 1
            rows_counter_check = rows_counter_check - 1
        else
            local foundone_room_table2 = false
            local foundone_room_table = false
            if room_num_table ~= nil and #room_num_table > 0 then
                for p = 1, #room_num_table do
                    if (string.lower(room_num_table[p][2]) == string.lower(nameHolder) or room_num_table[p][1] == area_table[z].uid)
                    and tableNum == tableNumHolder then foundone_room_table = true end-- cp_mobs[tableNum].name
                end
            end
            if #room_num_table2 > 0 and room_num_table2 ~= nil then
                for i = 1, #room_num_table2 do
                    if area_table[z].areaName == room_num_table2[i][5] or room_num_table2[i][1] == area_table[z].roomuid then-- see if the first condition needs and tableNum == tableNumHolder
                        
                        foundone_room_table2 = true
                        break
                    else
                        foundone_room_table2 = false
                    end
                end
            end
            if not foundone_room_table then
                table.insert(test_timeskileed, {area_table[z]})
                make1(roomNumber, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, true, area_table[z].areaName, cp_mobs[tableNum].num, #test_timeskileed or 0)
                DebugNote('roomNumber '..roomNumber)
                DebugNote('cp_mobs[tableNum].name '.. cp_mobs[tableNum].name)
                DebugNote('area_table[z].areaName '.. area_table[z].areaName)
                DebugNote('cp_mobs[tableNum].num '.. (cp_mobs[tableNum].num or 'nil'))
                tableNumHolder = tonumber(tableNum)
                mob_index = 1
            elseif not foundone_room_table2 then
                make2(roomNumber, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, true, area_table[z].areaName, cp_mobs[tableNum].num)
                mob_index = 1
            end
        end
    end
    tableNumHolder = tonumber(tableNum)
    mob_index = 1
    DebugNote("Times killed table")
    DebugNote(test_timeskileed)
    DebugNote("Times killed table === end")
end
room_not_in_database = {}

function sortRoomCPByPath()
    local x
    local room = -1
    dist_tbl1 = {}
    dist_tbl2 = {}
    dist_correction = {}
    DebugNote('==============================')
    DebugNote(currentRoom.roomid)
    for i, p in ipairs(room_num_table) do
        DebugNote(i)
        DebugNote(p)
        x, dep = findpath(currentRoom.roomid, p[1])
        DebugNote('Depth:')
        DebugNote (dep)
        if dep ~= nil then
            if p[7] == 1 then
                table.insert(dist_tbl1, {i, dep, p[5]})
            else
                table.insert(dist_tbl2, {i, dep, p[5]})
            end
        else
            DebugNote('printing p')
            DebugNote(p)
            DebugNote('printing cp_mobs')
            DebugNote(cp_mobs[i])
            if (cp_mobs[i].dist ~= nil) then
                if p[7] == 1 then
                    table.insert(dist_tbl1, {i, cp_mobs[i].dist, p[5]})
                else
                    table.insert(dist_tbl2, {i, cp_mobs[i].dist, p[5]})
                end
                --DebugNote('i is '..i .. ' p.dist is '.. p.dist.. ' p[5] '.. p[5])
                DebugNote("room_num_table " .. i .." = " .. cp_mobs[i].dist)
            else
                DebugNote('i is '..i .. ' p.dist is 501 p[5] '.. p[5])
                table.insert(dist_correction, {i, 501, p[5]})
            end
        end
    end
    local keys = {}
    local b = {}
    local q = {}
    for i, p in ipairs(dist_correction) do
        local stop_correction = 0
        for q, n in ipairs(dist_tbl2) do
            if (p[3] == n[3] and stop_correction == 0) then
                table.insert(dist_tbl2, {p[1], n[2]})
                stop_correction = 1
            end
        end
        if stop_correction == 0 then
            DebugNote('inserted '.. 501 .. ' from ' .. p[1])
            table.insert(dist_tbl2, {p[1], 501, p[3]})
        end
    end
    DebugNote(dist_tbl1)
    DebugNote(dist_tbl2)
    table.sort(dist_tbl1, function(a, b) return a[2] < b[2] end)
    for _, k in ipairs(dist_tbl1) do
        cp_mobs[k[1]].dist = k[2]
        DebugNote(cp_mobs[k[1]])
        table.insert(b, cp_mobs[k[1]])
        table.insert(q, room_num_table[k[1]])
    end

    table.sort(dist_tbl2, function(a, b) return a[2] < b[2] end)
    for _, k in ipairs(dist_tbl2) do
        -- print(cp_mobs_length+ k[1])
        cp_mobs[k[1]].dist = k[2]
        DebugNote(cp_mobs[k[1]])
        table.insert(b, cp_mobs[k[1]])
        table.insert(q, room_num_table[k[1]])
    end
    room_num_table = q
    cp_mobs = b
end

mob_index = tonumber(1)
mob_next_delete_value = nil

function do_Execute_no_echo(command)
    local original_echo_setting = GetOption("display_my_input")
    SetOption("display_my_input", 0)
    Execute(command)
    SetOption("display_my_input", original_echo_setting)
end

function gotoNextMob()-- This will goto the next mob, use with tcp
    if tonumber(char_status.state) == 8 then
        Note('Cannot run, you are still fighting')
        return
    end
    if cp_mobs == nil then
        Note ('Nothing to go to!')
        return
    end
    if mob_index == nil  or mob_index == '' then
        mob_index = 1
    end
    if room_num_table == nil or #room_num_table < 1 then
        return
    end
    if room_num_table[1][1] == -1 then
        Note ("Try tcpo or manually finding this mob.. use pto to check the other table")
        return
    end
    check_dead()
    if room_num_table[1][3] == false then
        if hunt_type(0, 0) == 1 then
            return
        end
        
        --Execute('xmapper1 move ' .. getTable(mob_index))
        local num, tbl_mob = getTable(mob_index)
        if num > 0 then
            tprint(tbl_mob)
            BroadcastPlugin(2, "Moving to "..tostring(num))
           if GOTO(num) ==0 then
                Note('Running to area..')

                Execute('xrunto1 '.. room_num_table[mob_index][5])
            end 
        else
            Note('There was an issue finding this mob.. check pt and talk to a developer')
        end
        DebugNote("Entry for mob_next_delete_value")
        DebugNote(mob_index)
        mob_next_delete_value = mob_index
        Send('scan ' .. mobname)
        
    else
        if hunt_type(0, 1) == 1 then
            return
        end
        --Execute('xmapper1 move ' .. getTable(mob_index + 1))
        -- print(mob_index)

        local num = getTable(mob_index+1)
        if num > 0 then
            BroadcastPlugin(2, "Moving to "..tostring(num))
            if GOTO(num) ==0 then
                Note('Running to area..')
                Execute('xrunto1 '.. room_num_table[mob_index+1][5])
            end 
        else
            Note('There was an issue finding this mob.. check pt and talk to a developer')
        end
        DebugNote("Entry for mob_next_delete_value")
        DebugNote(mob_index + 1)
        mob_next_delete_value = mob_index + 1
        SendNoEcho('scan ' .. mobname)
    end
end

function gotoIndexMob(name, line, wildcards)-- This will goto the next mob, use with tcp
    if tonumber(char_status.state) == 8 then
        Note('Cannot run, you are still fighting')
        return
    end
    wild = tonumber(wildcards[1])
    if wild == nil then return end
    if cp_mobs == nil or #cp_mobs == 0 then
        Note("Nothing to goto.")
        return
    end
    if room_num_table == nil or #room_num_table == 0 then
        return
    end
    if tonumber(wildcards[1]) < 0 or tonumber(wildcards[1]) > #room_num_table then
        wild = #room_num_table
    end
    if room_num_table[wild][1] == -1 then
        Note ("Try tcpo or manually finding this mob.. use pto to check the other table")
        return
    end
    check_diff()
    check_dead()
    if hunt_type(wild, 0) == 1 then
        return
    end
    DebugNote("Entry for mob_next_delete_value")
    DebugNote(wild)
    mob_next_delete_value = wild
    --Execute('xmapper1 move ' .. getTable(tonumber(wild)))
    local num = getTable(tonumber(wild))
    if num > 0 then
        BroadcastPlugin(2, "Moving to "..tostring(num))
        if GOTO(num) ==0 then
            Note('Running to area..')
            Execute('xrunto1 '.. room_num_table[wild][5])
        end 
    end
    SendNoEcho('scan ' .. mobname)
end

function tcpohandler(name, line, wildcards)
    if  tonumber(char_status.state) == 8 then
        Note('Cannot run, you are still fighting')
        return
    end
    if wildcards[1] ~= nil then
        if room_num_table2 == nil or #room_num_table2 == 0 then
            Note("nothing to print")
            return
        end
    end
    wild = tonumber(wildcards[1])
    if room_num_table2 == nil or #room_num_table2 == 0 then
        Note('nothing to print')
        return
    end
    if wildcards[1] == nil then
        wild = 1
    end
    if wild > #room_num_table2 then
        wild = #room_num_table2
    end
    if #wildcards >= 1 then
        mobname = sanitizeName(room_num_table2[tonumber(wild)][2])
        --Execute ('xmapper1 move ' .. room_num_table2[tonumber(wild)][1])
        local num = room_num_table2[tonumber(wild)][1]
        if num > 0 then
            if GOTO(num) ==0 then
                Note('Running to area..')
                Execute('xrunto1 '.. room_num_table2[wild][5])
            end 
        else
            Note('There was an issue finding this mob.. check pt and talk to a developer')
        end
        DebugNote("Entry for mob_next_delete_value")
        DebugNote(wild)
        mob_next_delete_value = wild
        --EnableTrigger('get_all_output', true)
        SendNoEcho('scan ' .. mobname)
    else
        mobname = sanitizeName(room_num_table2[1][2])
        --Execute ('xmapper1 move ' .. room_num_table2[1][1])
        local num = room_num_table2[1][1]
        if num > 0 then
            if GOTO(num) ==0 then
                Note('Running to area..')
                Execute('xrunto1 '.. room_num_table2[1][5])
            end 
        else
            Note('There was an issue finding this mob.. check pt and talk to a developer')
        end
        mob_next_delete_value = 1
        --EnableTrigger('get_all_output', true)
        SendNoEcho('scan ' .. mobname)
    end
end

function hunt_type (num, mob_id)
    if mob_index == 0 then
        local mob_index = 1
    else
        local mob_index = 2
    end
    if num ~= 0 then
        if type(room_num_table[tonumber(num)][1]) == 'string' then -- If An index query and room type
            DebugNote("Entry for mob_next_delete_value")
            DebugNote(num)
            mob_next_delete_value = tonumber(num)
            holder = getTable(num)
            if (string.find(string.lower(room_num_table[num][1]), string.lower(areas_tbl[currentRoom.areaid].name))) then
                Note('well this is awkward you are already in the correct area')
            else
                Execute('xrunto1 '..room_num_table[num][1])
            end
            cpn_script(tonumber(num))
            return 1
        end
    else
        if type(room_num_table[mob_index][1]) == 'string' then-- if NOT an indexed query and a room type
            DebugNote("Entry for mob_next_delete_value")
            DebugNote(mob_index)
            mob_next_delete_value = mob_index
            holder = getTable(mob_index)
            if (string.find(string.lower(room_num_table[mob_index][1]), string.lower(areas_tbl[currentRoom.areaid].name))) then
                Note('well this is awkward you are in the correct area')
            else
                Execute('xrunto1 '..room_num_table[mob_index][1])
            end
            cpn_script(mob_index)
            return 1
        end
    end
end

where_mob = ''
t_lookup_preloaded = {}

function load_tlookup(room, area)
    if area == nil then
        t_lookup_preloaded = {room, nil}
    else
        t_lookup_preloaded = {room, area}
    end
end

function whereMob(name, line, wildcards)
    tstart = GetInfo (232)
    hunt_off()
    auto_hunt_stop()
    kill_scan_run()
    where_mob = wildcards[1]
    if where_mob == nil then
        if mobname ~= nil then
            EnableTrigger('where_mob_trig', true)
            Execute('where ' .. mobname)
            
            DoAfterSpecial(2, "EnableTrigger('where_mob_trig', false)", 12)
        else
            Note ("Need to use tcp or tcp <index> first")
            return
        end
    else
        EnableTrigger('where_mob_trig', true)
        Execute('where ' .. where_mob)
        DoAfterSpecial(1, "EnableTrigger('where_mob_trig', false)", 12)
        where_mob = string.gsub(where_mob, "%d+%.", "")
        mobname = where_mob
    end
end

local where_black_list = {"Your magic is blessed with",
    "You feel less righteous as the",
    "You now possess magical powers",
    "You feel gills growing on your",
"You now detect the presence of"}

where_trig_table = {}
WHERE_MOB = ''
function where_mob_trig(name, line, wildcards)
    dbA = GetInfo (66) .. 'Aardwolf.db'
    for i, p in ipairs(where_black_list) do
        if (string.find(wildcards[0], p) ~= nil) then
            return
        end
    end
    
    wildcards[1], x = string.gsub(wildcards[1], "%.", "")
    WHERE_MOB = trim(wildcards[1])
    bool = 0
    for word in mobname:gmatch("%w+") do
        if (string.find(string.lower(wildcards[1]), string.lower(word)) ~= nil) then
            bool = 1
        end
    end
    
    if bool == 1 then
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
        
        if currentRoom.areaid == nil then return end
        qryArea = string.format(
            " select r.uid  as roomId   " ..
            "   from rooms r            " ..
            "   join areas a            " ..
            "     on a.uid = r.area     " ..
            "  where a.uid = %s        " ..
            "    and r.name = %s        " ..
            " order by roomId desc       ",
            fixsql(currentRoom.areaid),
        fixsql(wildcards[2]))
        
        where_trig_table = db_query(dbA, qryArea)
        if #where_trig_table == 0 then
            Note('The room you are trying to find seems to not be mapped')
            return
        end
        
        EnableTrigger('where_mob_trig', false)
        load_tlookup(wildcards[2], currentRoom.area)
        IS_WM_ENABLED = true
        wm_study_continue()
    end
end

function killMob()
    if mobname ~= nil then
        BroadcastPlugin(2,"Attacking ".. mobname)
        Execute("kill " .. mobname)
    else
        Note ("Need to use tcp first")
    end
end

areaLevel = {}

-- In case of a mob not in the db then these will get used
count = 1
function incrementCounter()
    count = count + 1
    Execute("hunt " .. count.."." .. mobname)
end

function reset_counter()
    count = 1
end
CPMobs = {}
CPMobs1 = {}
CPMobsIndex = 1
vnum_holder = 0
function reset_index()
    CPMobsIndex = 1
    CPMobs1 = {}
end

cpn_is_room_type = false
cpn_is_room_type_table = {}
cpnrtt = 1

function hunt_from_link(area)
    DebugNote (area)
    Execute("xrunto1 " .. area)
    Execute ("hunt " .. mobname)
end

dbA = GetInfo (66) .. 'Aardwolf.db'
dbkt = GetPluginInfo (GetPluginID (), 20) .. 'KillTable.db'
rooms_tbl = {1, 1}
areas_tbl = {}
mobktbl = {}

function StartScript()
    do_Execute_no_echo('map')
    do_Execute_no_echo("cp check")
    
    GetPageSize()
    SendNoEcho('tags scan on')
    areaLevel = db_query_area(dbkt, "select keyword, name, afrom, ato, alock from areas")
    Note (GetPluginInfo (GetPluginID (), 20))
    qry = "select * from rooms where uid not like '*' and uid not like '**' order by uid"
    qry2 = "select * from areas"
    qry3 = "select *, count(*) as timeskilled from mobkills group by name,room_id order by name, timeskilled desc"
    CpMobsAbr(mylevel)
    rooms_tbl = {}
    rooms_tbl = db_query_rooms(dbA, qry)
    areas_tbl = db_query_areas(dbA, qry2)
    mobktbl = db_query(dbkt, qry3)
    
    if not IsPluginInstalled("0961770926b613688a1c5458") then
        LoadPlugin(GetPluginInfo (GetPluginID (), 20) .. "cp_mobTableFiller.xml")
    end
    if not IsPluginInstalled("eee3a98a021c1bee534ef09f") then
        LoadPlugin(GetPluginInfo (GetPluginID (), 20) .. "TOLminwin.xml")
    end
    
end

function OnPluginDisable ()
    SendNoEcho('tags scan off')
end -- OnPluginDisable

function OnPluginInstall()
    -- print('cleaning the table')
    -- check_file = io.open("Tol_log.txt", "r")
    
    file = io.open("Tol_log.txt", "w+")
    print("Clearing Tol_log file.")
    io.close(file)
    check_area_table()
    Clean_Kill_Table()
    -- Connected? GMCPHandler Enabled? Not initialized yet? Request the GMCP for initialization -Kobus
    if IsConnected() and GetPluginInfo("3e7dedbe37e44942dd46d264", 17) and not didonce then
        Execute("sendgmcp request room")
        Execute("sendgmcp request char")
    end
end

function OnPluginBroadcast (msg, id, name, text)
    --DebugNote ("msg = " .. msg)
    --DebugNote ("id = " .. id)
    --DebugNote ("name = " .. name)
    --DebugNote ("text = " .. text)
    
    if id == 'b6eae87ccedd84f510b74714' then
        if text == 'kinda_busy' then
            DebugNote("kinda_busy")
            CAN_RUN = false
        elseif text == 'ok_you_can_go_now' then
            DebugNote("ok_you_can_go_now")
            -- if IS_WM_ENABLED then
            --     wm_study_continue()
            -- end
            CAN_RUN = true
        end
    end
    
    if (id == '3e7dedbe37e44942dd46d264') then
        if (text == "comm.repop") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "comm.repop")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            BroadcastPlugin(2, gmcpdata.zone .. " has repoped.")
        end
        if (text == "comm.quest") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "comm.quest")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            if (gmcpdata.action == "start") then
                BroadcastPlugin(2,"You took a Quest. Go kill " .. gmcpdata.targ)
                timeStart()
            end
            if (gmcpdata.action == "comp") then
                BroadcastPlugin(2,"Quest Completed.")
                timeEnd()
            end
            if gmcpdata.action == "killed" then
                BroadcastPlugin(2,"Quest Target Killed, Turn it in.")
            elseif gmcpdata.action == "warning" then
                BroadcastPlugin(2,"Running out of time, finish quest.")
            elseif gmcpdata.action == "ready" then
                BroadcastPlugin(2,"You can quest again.")
            elseif gmcpdata.action == "fail" then
                BroadcastPlugin(2,"You failed a quest.") 
            elseif gmcpdata.action == "timeout" then
                BroadcastPlugin(2,"You ran out of time for a quest.")  
            end   
        end
        if (text == "room.info") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "room.info")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            currentRoom = {
                name = gmcpdata.name,
                roomid = gmcpdata.num,
                areaid = gmcpdata.zone
            }
            ensure_room_change = -1
            got_room = true -- Got the room data - Kobus
        end
        if (text == "char.status") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char.status")
            luastmt = "gmcpdatacharstatus = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            char_status = gmcpdatacharstatus
            mylevel = tonumber(gmcpdatacharstatus.level)
        end
        if (text == "char.base") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char.base")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            mytier = tonumber(gmcpdata.tier)
            got_char = true -- Got the char data - Kobus
        end
        if mylevel ~= oldlevel and didonce == true then -- We leveled?, rebuild CPMobs table
            DebugNote("Rebuilding cpmobs table...")
            CpMobsAbr(mylevel) -- Rebuild the CPMobs table - Kobus
        end
        
        if (text == "char.base") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char.base")
            luastmt = "gmcpdatacharstatus = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            char_base = gmcpdatacharstatus
        end
        if got_room and got_char and not didonce then didonce = true Note("start") StartScript() end -- Got what we needed from GMCP, initialize the TOL script -- Kobus
    end
end

function myHandler(udata, retries)
    DebugNote("BUSY!")
    return true
end
function OnPluginClose ()
    
end

function reset_cp_win()
    BroadcastPlugin(4)
    FirstRun_cp_var = true
end

function reset_cp_flag()
    BroadcastPlugin(4)
    timeEnd()
    FirstRun_cp_var = true
end

function collectgarbagenow()
    --Note( collectgarbage("count")*1024)
    collectgarbage("collect")
    --Note( collectgarbage("count")*1024)
end

function DebugNote(msg)
    file = io.open("Tol_log.txt", "a")
    --Note(type(msg))
    if type(msg) == 'table' then
        -- file:write("in if for table\n")
        -- file:write(type(msg))
        -- file:write("\n")
        --Note("in if for table")
        local function tlog (t, indent, done)
         -- in case we run it standalone
      
            -- file:write("in tlog\n")
            --Note("in tlog")
            -- show strings differently to distinguish them from numbers
            local function show (val)
                -- file:write("in show")
                --Note("in show")
                if type (val) == "string" then
                  return '"' .. val .. '"'
                else
                  return tostring (val)
                end -- if
            end -- show
          -- entry point here
            --Note("in start of tlog")
            done = done or {}
            indent = indent or 0
            for key, value in pairs (t) do
                -- print("in for in table script")
                file:write (string.rep (" ", indent)) -- indent it
                if type (value) == "table" and not done [value] then
                  done [value] = true
                  file:write (show (key), ":")
                  tlog (value, indent + 2, done)
                else
                  file:write (show (key), "=")
                  file:write (show (value))
                end
                file:write("\n")
            end
        end
        --Note("hitting tlog")
        tlog(msg)    
    else 
        if msg == nil then 
            file:write("nil\n")
        else
            file:write(tostring(msg) .. "\n")
        end
    end
    io.close(file)
    if not Debug then return end
    if type(msg) == 'table' then
        tprint(msg)
    else
        Note (msg)
    end
   
end

-----------------------------------------------------------
-- Scanning and highlighting
-----------------------------------------------------------
function kill_scan_run()
    BroadcastPlugin(2,"Shutting off scan related scripts.")
    WHERE_MOB = ''
    where_trig_table = {}
    SCAN_TABLE = {}
end
function scan_break()
    BroadcastPlugin(2,"Movement failed, check path.")
    auto_hunt_stop()
    kill_scan_run()
    hunt_off()
    EnableTriggerGroup("study_output", 0)
end
function has_value(tab, val)
    DebugNote("Match value: " .. val)
    
    -- Check for custom wm attend.
    --if #where_trig_table >= 1 then
    DebugNote('WHERE_MOB: ' .. WHERE_MOB)
    if string.match(replace(val), string.lower(replace(WHERE_MOB))) then
        DebugNote("Where_mob match.")
        return true
    else
        return false
    end
    --end
    
    -- Check quest mob
    if questHandler.mob ~= nil and string.match(replace(val), string.lower(replace(questHandler.mob))) then
        DebugNote("Quest match.")
        return true
    end
    
    -- Check for cp mobs.
    for index, value in pairs(tab) do
        if value == nil then return end
        
        if string.match(replace(val), string.lower(replace(value.name))) then
            DebugNote("Cp match.")
            return true
        end
    end
    
    DebugNote("No match found.")
    return false
end
action = ''
function wm_study_continue(send_study)
    wait.make (function()
        DebugNote("wm_study_continue")
        local send_study = send_study or true
        if #where_trig_table >= 1 then
            DebugNote('Where_trig_table Size: ' .. #where_trig_table)
            if not currentRoom.roomid == where_trig_table[1].roomId then
                mapper_goto(where_trig_table[1].roomId)
                table.remove(where_trig_table, 1)
            end
            
            EnableTriggerGroup("study_output", 1)
            DebugNote('study_output on')
            
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char.status")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            runningFlag = tonumber(gmcpdata.state)
            if runningFlag == 8 then
                kill_scan_run()
                where_trig_table = {}
                return
            end
            if IS_WM_ENABLED then
                DebugNote("From: " .. currentRoom.roomid)
                DebugNote("Going to: " .. where_trig_table[1].roomId)
                BroadcastPlugin(2, "Moving to "..tostring(where_trig_table[1].roomId))
                if GOTO(where_trig_table[1].roomId) == 0 then
                    table.remove(where_trig_table, 1)
                    wm_study_continue(3)
                    return
                end
                line, wildcards = wait.regexp("^\\{where restart\\}",nil,trigger_flag.OmitFromOutput)
                table.remove(where_trig_table, 1)
            else
                AddTrigger("catchwhererestart", "^\\{where restart\\}", "", trigger_flag.OmitFromOutput+trigger_flag.OneShot , "", 0, "", "")
                DebugNote('added where restart catch')
            end
            DebugNote(tostring(send_study))
            if send_study ~= 3 then
                Send("study " .. mobname)
            end
        else
            DebugNote("Searching finished.")
        end
    end)
end

function istarget_study(name, line, wildcards, style)
    DebugNote("function: ISTARGET_STUDY")
    EnableTriggerGroup("study_output", 0)
    DebugNote('study_output off')
    EnableTrigger('get_all_output', false)
    DebugNote('get_all_ouput off')
    -- Disable get_all_output trigger if line is empty.
    if wildcards[0] == "" then
        IS_WM_ENABLED = true
        EnableTrigger('get_all_output', false)
        DebugNote('get_all_ouput off')
        DebugNote("--END OF STUDY--")
        return
    end
    local mob_here = false
    local name = string.sub(string.lower(wildcards[1]), 1, 30)
    
    if has_value(cp_mobs, name) then
        DebugNote("MOB IS HERE!")
        IS_WM_ENABLED = false
        mob_here = true
        -- Delete the timers from wm_study_continue()
        DeleteTemporaryTimers();
        
        -- Calculate the time elapsed from the start of wm till now.
        -- Only for Debugging purposes.
        if tstart then
            tend = GetInfo (232)
            Note(string.format ("Time taken = %1.3f seconds", tend - tstart))
        end
        
        -- Print target mob with colours.
        for a, s in ipairs(style) do
            local text = RGBColourToName(s.textcolour)
            local back = RGBColourToName(s.backcolour)
            text = "black" back = "yellow"
            ColourTell(text, back, s.text )
        end
        if highlight then ColourTell("black", "yellow", " [TARGET]") end
    Note()
        EnableTriggerGroup("get_all_output", 0)
        DebugNote('get_all_output off')
        EnableTrigger('where_mob_trig', 0)
        kill_scan_run()
        if mob_here then
            BroadcastPlugin(2,"Found Mob")
        end
    end
end
function replace (data)
    changed = string.gsub(data,"%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
    return changed
end
function istarget(name, line, wildcards, style)
    DebugNote("function: ISTARGET")
    local highlight = false
    local name = string.lower(wildcards[1])
    local target_mobs = {}
    if questHandler.mob ~= nil then target_mobs = {string.lower(questHandler.mob)}
    end
    if #cp_mobs >= 1 then
        for a = 1, #cp_mobs do table.insert(target_mobs, string.lower(cp_mobs[a].name))
        end
    end
    if #where_trig_table >= 1 then -- used for the wm and cpn commands
        DebugNote('WHERE_MOB: ' .. WHERE_MOB)
        table.insert(target_mobs, WHERE_MOB)-- the global mob name
        DebugNote(wildcards)
    end
    for a = 1, #target_mobs do
        if #name > 30 then
            DebugNote('name before: ' .. name)
            name = string.sub(name, 1, 30)
            DebugNote('name after: ' .. name)
        end
        DebugNote(string.lower(name))
        DebugNote(string.lower(target_mobs[a]))
        
        if string.lower(replace(name)) == string.lower(replace(target_mobs[a])) then
            highlight = true
            EnableTriggerGroup("get_all_output", 0)
            DebugNote('get_all_output off')
            break
        end
    end
    for a, s in ipairs(style) do
        local text = RGBColourToName(s.textcolour)
        local back = RGBColourToName(s.backcolour)
        if highlight then text = "black" back = "yellow" end
        ColourTell(text, back, s.text)
        DebugNote({text, back, s.text})
    end
    if highlight then ColourTell("black", "yellow", " [TARGET]") end
    Note()
end
-----------------------------------------------------------
-- Questing
-----------------------------------------------------------

-- Questing Triggers
function QuestInfoHandle(name, line, wildcards)
    questHandler:setMob(wildcards[1])
    questHandler:setRoom(wildcards[2])
end

function QuestInfoHandleArea(name, line, wildcards)
    questHandler:setArea(wildcards[1])
end

function questMob(name, line, wildcards)
    questHandler:setMob(wildcards[1])
end

function questRoom(name, line, wildcards)
    questHandler:setRoom(wildcards[2])
end

function questArea(name, line, wildcards)
    questHandler:setArea(wildcards[1])
end

function qGoto()
    BroadcastPlugin(2, "Moving to quest mob")
    mobname = sanitizeName(questHandler.mob)
    questHandler:gotoFirst()
end

function qGotoIndex(name, line, wildcards)
    local idx = tonumber(wildcards[1])
    if idx == nil then return end
    
    mobname = sanitizeName(questHandler.mob)
    questHandler:gotoIndex(idx)
end

function qNext()
    BroadcastPlugin(2, "Moving to next quest mob")
    mobname = sanitizeName(questHandler.mob)
    questHandler:gotoNext()
end

function qRooms()
    questHandler:showRooms()
end

function qRoomsAll()
    questHandler:showRooms(true)
end

function qClear()
    questHandler:clear()
end

function qTest()
    questHandler:setMob("the Liavango Despot")
    questHandler:setRoom("Home of the Despot")
    questHandler:setArea("The Darkside of the Fractured Lands")
end
