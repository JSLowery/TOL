require "tprint"
require "gmcphelper"
require "wait"
local areaid
local roomid
local roomname
local cpmobs
local locked_enemy
-- print("test")
-- print(GetPluginInfo (GetPluginID (), 20))
function last_kill()
    EnableTriggerGroup("gag_lastkill", true)
    SendNoEcho("lastkill 1")
    if currentRoom == nil then
        res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "room.info")
        luastmt = "gmcpdata = " .. gmcparg
        assert (loadstring (luastmt or "")) ()
        --tprint (gmcpdata)
        currentRoom = {
            name = gmcpdata.name,
            roomid = gmcpdata.num,
            areaid = gmcpdata.zone
        }
    end
    lockedRoom = {}
    for i, p in pairs(currentRoom) do
        lockedRoom[i] = p
    end
    if current_enemy_gbl ~= nil then
        Note("Locking enemy")
        locked_enemy = current_enemy_gbl
        Note(current_enemy_gbl)
        Note("locked")
    end
    --EnableTrigger("capture_name", 0)
end
function myHandler(udata, retries)
    return true
end
function Add_To_Table(name, line, wildcards)
    local name = Trim(wildcards[1])
    local level = wildcards[3]
    local area
    local roomid
    local roomName
    dbA = sqlite3.open(GetInfo (66) .. 'Aardwolf.db')
    dbkt = sqlite3.open(GetPluginInfo (GetPluginID (), 20) .. 'KillTable.db')
    dbkt:busy_handler(myHandler)
    dbkt:busy_timeout(500)
    EnableTriggerGroup("gag_lastkill", false)
    name = locked_enemy or name
    area = lockedRoom.areaid
    query = string.format("SELECT name from areas where uid = %s", fixsql(area))
    for rows in dbA:nrows(query) do
        area = rows.name
    end --for
    if name == '' then
        print('Something has gone wrong, not inserting anything')
        name = nil
        roomid = nil
        roomName = nil
        area = nil
        level = nil
        dbA:close()
        dbkt:close()
        return
    end
    roomName = string.gsub(lockedRoom.name, "%@([a-zA-Z])", "")
    roomid = lockedRoom.roomid
    if check_mob_exists(name, roomid, dbkt) then
        stmt = "UPDATE CPMobs set timeskilled = timeskilled+1, level = (level+%i)/2 where name = %s and room_id = %s"
        stmt = string.format(stmt, tonumber(level), fixsql(name), fixsql(roomid))
        rc = dbcheck(dbkt:exec(stmt), dbkt)
        if rc ~= 0 then
            Note (DatabaseError('dbkt'))
            print (query)
            print (stmt)
            print (name)
            print (roomid)
            print (roomName)
            print (area)
            print (level)
            print (dbkt:errcode())
            print (dbkt:errmsg())
        end--if
    else
        stmt = "INSERT INTO CPMobs(name, room_id, room_name, area_name, level, keywords, timeskilled) VALUES(%s,%s,%s,%s,%s,'', 1)"
        stmt = string.format(stmt, fixsql(name), tonumber(roomid), fixsql(roomName), fixsql(area), tonumber(level))
        rc = dbcheck(dbkt:exec(stmt), dbkt)
        if rc ~= 0 then
            Note (DatabaseError('dbkt'))
            print (query)
            print (stmt)
            print (name)
            print (roomid)
            print (roomName)
            print (area)
            print (level)
            print (dbkt:errcode())
            print (dbkt:errmsg())
        end--if
    end
    print(stmt)
    name = nil
    roomid = nil
    roomName = nil
    area = nil
    level = nil
    dbA:close()
    dbkt:close()
    --EnableTrigger("capture_name", 1)
end
function dbcheck (code, dbkt)
    if code ~= sqlite3.OK and -- no error
        code ~= sqlite3.ROW and -- completed OK with another row of data
        code ~= sqlite3.DONE then -- completed OK, no more rows
        local err = dbkt:errmsg () -- the rollback will change the error message
        dbkt:exec ("ROLLBACK") -- rollback any transaction to unlock the database
        error (err, 2) -- show error in caller's context
    end -- if
    return code
end -- dbcheck
function check_mob_exists(name, roomid, dbkt)
    query = 'select count(1) as count from CPMobs where name = %s and room_id = %s'
    query = string.format(query, fixsql(name), tonumber(roomid))
    count = 0
    for c in dbkt:nrows(query) do
        count = c.count
    end
    if count < 1 then
        return nil
    end
    return 1
end
function fixsql (s)
    if s then
        return "'" .. (string.gsub (s, "'", "''")) .. "'" -- replace single quotes with two lots of single quotes
    else
        return "NULL"
    end -- if
end -- fixsql
function concat_name(name, line, wildcards, styles)
    local test_table = {}
    str = ""
    for i, p in pairs(styles) do
        --tprint(p)
        --ColourTell(RGBColourToName(p.textcolour), RGBColourToName(p.backcolour),p.text)
        --str = str .. ","..p.textcolour..","..p.text
        table.insert(test_table, {
            p.text,
            RGBColourToName(p.textcolour),
        RGBColourToName(p.backcolour)})
    end
    found = false
    current_enemy_gbl = check_cur_mob(test_table)
    -- tprint(test_table)
end
function check_cur_mob(test_table)
    if not enemy then 
        enemy = ""
    end
    cur_mob = nil
    --For note, people should use damage output that isn't basic.. this is supposed to be an unused
    -- section of code.
    if #test_table == 3 then
        local line = test_table[1][1]
        if string.find(line, "%!") ~= nil then
            temp= string.sub(line, 8, string.find(line, "%!")-1 )
        elseif string.find(line, "%.") then
            temp= string.sub(line, 8, string.find(line, "%.")-1 )
        end--if
        for i,v in pairs(damage_verbs) do
            o, p =string.find(temp, v)
            if p ~= nil then
                temp = string.sub(temp, p+1, #temp)
                return temp
            end--i
        end--for
        i = string.find(temp, "%A")
        while i  do
            temp= string.sub(temp, i+1, #temp )
            i=string.find(temp, "[%A][%s]")
        end -- while
        temp= string.sub(temp, 2, #temp )
        return temp
    end
    for i, p in pairs(test_table) do
        test_color = string.sub(p[1], -2, -2)
        if i>1 and p[2] == test_table[1][2] and (test_color == '!' or test_color == '.') then
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
-- TODO: this function needs to be updated..
function init()
    dbkt = sqlite3.open(GetPluginInfo (GetPluginID (), 20) .. 'KillTable.db')
    rc = dbkt:exec([[
            drop table if exists
            CREATE TABLE CPMobs(
              mk_id INTEGER NOT NULL PRIMARY KEY autoincrement,
              name TEXT default "Unknown",
              room_id INTEGER default 0, 
              room_name TEXT default "Unknown",
              area_name TEXT default "Unknown",
              level INTEGER default 0,
              keywords Text degault "",
              timeskilled INTEGER;"
          ]])
    if rc ~= 0 then
        Note (DatabaseError('dbkt'))
    end--if
    dbkt:close()
end
function OnPluginBroadcast(msg, id, name, text)
    if (id == '3e7dedbe37e44942dd46d264') then
        if (text == "char.status") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char.status")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            if gmcpdata.state == '8' then
                -- print(gmcpdata.enemy)
                enemy = gmcpdata.enemy
            end
        end
        if (text == "room.info") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "room.info")
            luastmt = "gmcpdata = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            --tprint (gmcpdata)
            currentRoom = {
                name = gmcpdata.name,
                roomid = gmcpdata.num,
                areaid = gmcpdata.zone
            }
            --tprint (currentRoom)
        end
        
    end
    if id == "8065ca1ba19b529aee53ee44" then
        if msg == 1 then
            local pvar = GetPluginVariable("8065ca1ba19b529aee53ee44", "cp_mobs")
            loadstring(pvar)()
            cpmobs = cp_mobs
        end--if
    end
end
function OnPluginInstall()
    dbkt = sqlite3.open(GetPluginInfo (GetPluginID (), 20) .. 'KillTable.db')
    rc = dbkt:exec([[SELECT name FROM CPMobs ]])
    if rc ~= 0 then
        
        init()
    end--if
    --dbA=sqlite3.open(GetInfo (66) ..'Aardwolf.db')
    dbkt:close()
end
function OnPluginClose ()
    if dbkt ~= nil and dbkt:isopen() then
        dbkt:close()
    end
    if dbA ~= nil and dbA:isopen() then
        dbA:close()
    end
end
--I hate you, yes you. You use a basic output for damage and are forcing me
-- to use this akward and unmaintainable table..
damage_verbs = {'misses ',
    ' damages ',
    ' damage ',
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
