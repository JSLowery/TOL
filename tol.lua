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
ThreadHolder= coroutine.running()
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
mobsleft= {}
cp_mobs= {}
local qmob

timestart= 0
timeend= 0
auto_hunt_mob = ""

-- PageSize code
page_size = 0
kill_pagesize = 0

function GetPageSize()
  kill_pagesize = 0
  EnableTriggerGroup("page_size",1)
  SendNoEcho("pagesize")
end

function ResetPageSize()
  if page_size ~= 0 then
    SendNoEcho("pagesize " .. page_size)
  end
end

function auto_hunt_start(name, line, wildcards)
    Note("Starting autohunt")
    EnableTrigger('auto_hunt', 1)
    EnableTrigger('kill_auto_hunt', 1)
    auto_hunt_mob = wildcards[1]
    SendNoEcho('hunt '.. auto_hunt_mob)
    
end

function auto_hunt_continue(name, line, wildcards)
    local move = ""
    for i,p in pairs(wildcards) do
        DebugNote(p)
        DebugNote(i)
        if p ~= "" and i > 0 then
            move = wildcards[i+1]
            DebugNote(move)
            break
        end
    end
    if string.find(move, 'through') then
        if currentRoom ~= nil then
            query = string.format("select dir from exits where fromuid = %s order by length(dir) desc",
                currentRoom.roomid)
            move =db_query(dbA, query)
            DebugNote(move)
            if #move >1 then
                move = move[1]["dir"]
            end
        end
    end
    DebugNote(move)
    SendNoEcho(move)
    SendNoEcho('hunt '..auto_hunt_mob)
end

function auto_hunt_stop()
    Note("Shutting off Auto Hunt")
    EnableTrigger("auto_hunt",0)
    EnableTrigger("kill_auto_hunt",0)
end

function hunt_off()
  Note('Turning off cpn script.')
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
  return tostring(math.floor(dec*100))
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
  print ('Completion Time: '..timetostr(timeend-timestart))
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

function cp_check( name, line, wildcards)
  EnableTrigger("campaign_item", true)
  mobsleft = {}
end -- cp_check

function gq_check( name, line, wildcards)
  DebugNote( "gq_check")
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

  elseif #wildcards <=1 then
    EnableTrigger("campaign_item", true)
    Send("gq ch")
    mobsleft = {}
  elseif tonumber(wildcards.num) ~= tonumber(GQ_num) then
    GQ_flag = false
    DebugNote("Shutting GQ_flag off")
    EnableTrigger('camp_item_start', 0)
  end
end -- gq_check

function gq_start(name, line, wildcards)
  DebugNote ("gq_start")
  --EnableTrigger("campaign_item", true)
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
  phelper:broadcast(4)
  cp_mobs = {}
  clearTable()
end

function gq_end(name, line, wildcards)
DebugNote(wildcards)
  if GQ_flag == false then return end
  if wildcards[1] == GQ_num then
    DebugNote("if block")
    GQ_flag = false
    DebugNote("GQ_flag set to "..tostring(GQ_flag))
    phelper:broadcast(4)
    cp_mobs = {}
    clearTable()
  elseif #wildcards<1 then
    DebugNote("elseif block")
    GQ_flag = false
    DebugNote("GQ_flag set to "..tostring(GQ_flag))
    phelper:broadcast(3)
  end -- if
  DebugNote ("Gq is off now")
end

function add_Keywords(name, line, wildcards)
  if check_CPMobs_Table()<1 then
    print ("you don't have CPMobs table, you can't use this function, try installing the CPMobs plugin")
    return
  end
  query = string.format("UPDATE CPMobs SET keywords=%s WHERE name=%s;", fixsql(wildcards[2]), fixsql(wildcards[1]))
  querycheck = string.format("Select count(1) as count from CPMobs where name= %s;",fixsql(wildcards[1]))
  count = db_query(dbkt, querycheck)
  count = count[1].count
    if count<1 then
      print ("You have the name wrong, or it is not in the table, try again!")
      print ("You entered: " .. wildcards[1])
    end
  if tonumber(count)<1 then
    return
  end
  db_exec(dbkt, query)
  
  print ("Added ".. wildcards[2].. " to the mob entry for ".. wildcards[1])
end

function check_CPMobs_Table()
  local count = 0
  local checktable = "SELECT Count(1) as count FROM sqlite_master WHERE type='table' AND name='CPMobs';"
  count = db_query(dbkt, checktable)
  count = count[1].count
    if count <1 then
        return 0
    end
    return 1
end

function camp_item_start()-- get your campaign items
  clearTable()

  EnableTrigger('campaign_item',false)
  EnableTrigger('camp_item_start',0)
  cp_mobs = {}
  cp_mobs= mobsleft

    -- This is the first call to buildToomTable()
    buildRoomTable()


    FirstRun_cp_var= false
    check_dead()
    DebugNote(collectgarbage("count")*1024)
    collectgarbage("collect")
    DebugNote(collectgarbage("count")*1024)

end

function campaign_item (name, line, wildcards)-- the actual campaign item getter
  DebugNote("start cp_item mobsleft")
  DebugNote (wildcards)
  DebugNote("end cp_item mobsleft")
  name = wildcards.name
  mobdead = false
  location = wildcards.location
  num = tonumber(wildcards.num)
  if wildcards.dead ==  ' - Dead' then
    mobdead = true
  else
    mobdead = false
  end

  if not name or not location then
    print("error parsing line: ", line)
  else
    table.insert(mobsleft, {name=name, location=location, mobdead=mobdead, mobdead=mobdead,false, num = tonumber(num)})
  end
  end -- campaign_item

function delete_mob_from_table( )
  local found = false
  local tmp = {}
  local num
  if AutoUpdate_var == false and last_Enemy~= nil then
    for p,q in pairs (room_num_table) do
      num = tonumber(q[6]) or 1
      DebugNote (q)
      DebugNote(q[6])
      DebugNote ("Number of kills needed at time of delete_mob_from_table "..num)
      if string.lower(last_Enemy)== string.lower(q[2]) and num == 1 then
        table.remove(room_num_table,  p)
        table.remove(cp_mobs, p)
        found = true
        break
      elseif string.lower(last_Enemy)== string.lower(q[2]) then
        q[6] = q[6]-1
        cp_mobs[p].num = cp_mobs[p].num -1
        DebugNote(cp_mobs)
        DebugNote(cp_mobs[p][q])
        DebugNote ("number of mobs is ".. q[6])
        found = true
        break
      end--if
    end--for
    for p,q in pairs (room_num_table2) do
       if string.lower(last_Enemy)== string.lower(q[2]) then
        room_num_table2[p] = nil
        else
          table.insert(tmp, room_num_table2[p])
        end--if
    end--for
    room_num_table2 = tmp
    if found == false then
      DebugNote("Begin cp_mobs[mob_next_delete_value] check")
      DebugNote(num)
      DebugNote("End cp_mobs[mob_next_delete_value] check")
      table.remove(room_num_table,  mob_next_delete_value)
      table.remove(cp_mobs, mob_next_delete_value)
      DebugNote(GQ_flag)
      if GQ_flag == true then
        do_Execute_no_echo("gq check")
      else
        do_Execute_no_echo("cp check")
      end--if
    end--if
    mob_index= 1
  end--if
  check_diff()
  sortRoomCPByPath()
  var.cp_mobs = serialize.save( "cp_mobs", cp_mobs )
  phelper:broadcast(1, var.cp_mobs)
  DebugNote(collectgarbage("count")*1024)
  collectgarbage("collect")
  DebugNote(collectgarbage("count")*1024)
end

function delete_mob_from_table_index(val)
  if AutoUpdate_var == false and last_Enemy ~= nil then
  for p,q in pairs (room_num_table2) do
    num = tonumber(q[6]) or 1
     if string.lower(last_Enemy)== string.lower(q[2]) then
        table.remove(room_num_table2,  p)
      end--if
  end--for
  if room_num_table[val].num == 1 then
    table.remove(room_num_table, tonumber(val))
  else
    room_num_table[val][6] = room_num_table[val][6] -1
    cp_mobs[val].num = cp_mobs[val].num -1
  end
  DebugNote(collectgarbage("count")*1024)
  collectgarbage("collect")
  DebugNote(collectgarbage("count")*1024)
  mob_index= 1
  check_diff()
  end--if
end

function CPFound()
  if tonumber(count) >0 then
  Execute ("wm " .. count .. "." ..mobname)
  else
  Execute ("wm "  ..mobname)
  end
  EnableTriggerGroup("HUNTING", false)
end

function not_here_script()
  Execute("wm "..mobname)
  Note ("THIS IS NOT THE CORRECT AREA OR THE MOB IS DEAD")
  EnableTriggerGroup("HUNTING", false)

end

function quest_color()
  ColourNote ("white","blue","==================QUEST MOB HERE!!!!!!!!!!!!!!!!!!!!!!!=================")
end

function cpn_script (index, line, wildcards)
  local numcheck
  if wildcards ~= nil then
    numcheck = tonumber(wildcards[1])
  end
  DebugNote (index)
  DebugNote (type(index))
  DebugNote (numcheck)
    if  index ~= nil and type(index)== 'string'  then
        if #wildcards < 1 then
          index = mob_index

        elseif #wildcards <=1 and numcheck == nil then

          EnableTriggerGroup("HUNTING", true)
          reset_counter()
          mobname = wildcards[1]
          Execute ("hunt " .. mobname)
          --EnableTriggerGroup("HUNTING", false)
          return
        end
      if wildcards[1]== nil and mob_index ~= nil then
      else
      index = wildcards[1]
      end
    end --if
index = tonumber(index)
if room_num_table[index] == nil then
  print ("No cp_mob at that value")
  return
end--if
  EnableTriggerGroup("HUNTING", true)
  reset_counter()
  if room_num_table[index][1] ~= nil and cpn_is_room_type == false then
    getTable(index)
    Execute ("hunt " .. mobname)
  else
    Note("Either not on a cp or haven't checked it yet, or its a room type cp. Use hyperlink.")
    cpn_is_room_type= false
    EnableTriggerGroup("HUNTING", false)
  end
end

AutoUpdate_var = false
greedy = false
FirstRun_cp_var= true
-- This function is just for testing. It should never actually be used.
function printVars()
  -- mobsleft = {}
  -- EnableTrigger('campaign_item',1)
  -- EnableTrigger('camp_item_start',1)
  check_area_table()
end
-- end testing function
kill_info = {}
-- I hate to do it this way and will come up with a better solution... but for now
damage_verbs = {'misses ',
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
' annihilates ',-- nnih%
' evaporates ',-- vapor%
' ruptures ',-- upt%
' shatters ',-- hatter%
' slaughters ', -- laughters%
' vaporizes ',--vapor%
' wastes ',-- astes%
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
        --tprint(p)           
        if i>1 and p[2] == 'green' then
            cur_mob = string.sub(p[1], 0, -3)
            if cur_mob ~= enemy and cur_mob ~= 'Someone' then
                --print("I have been settt", cur_mob)
                ret = cur_mob
            elseif enemy ~= current_enemy_gbl then
                --print("I have been resettt", enemy)
                ret = enemy
            -- else
            --     Note(current_enemy_gbl)
            --     Note(enemy)
            end
        end
    end

    if cur_mob == nil and enemy ~= nil then
       -- print('both were nil setting to enemy')
        ret = enemy
    end
    return ret
end
function mob_name(name,line,wildcards, styles)
  local test_table = {}
    for i,p in pairs(styles) do
        --tprint(p)
        --ColourTell(RGBColourToName(p.textcolour), RGBColourToName(p.backcolour),p.text)
        --str = str .. ","..p.textcolour..","..p.text
        table.insert(test_table,{
            p.text,
            RGBColourToName(p.textcolour),
            RGBColourToName(p.backcolour)
        })
    end
    last_Enemy= check_cur_mob(test_table)
end

function Add_To_Kill_Table(name, line, wildcards)
  if greedy == false then
    return
  end--if
  kill_info.room_id= currentRoom.roomid
  kill_info.name= last_Enemy
  Add_Kill_Table(kill_info)
end

function check_dead ()
  check_diff()
  for p, q in ipairs(room_num_table) do
    if cp_mobs[p].mobdead ~= nil then
      if  q[2] == cp_mobs[p].name and cp_mobs[p].mobdead == true  then --used to be k.name and k.mobdead in case it doesn't work
        room_num_table[p][3] = true
      else
        room_num_table[p][3]= false
      end--if
    end
  end--for
end
-- TODO: Evaluate if this function is actually needed anymore.
function check_diff()
  if AutoUpdate_var== true then
    return
  end--if
    for p, q in pairs(room_num_table) do

      if cp_mobs[p]== nil then
         --print (p)
        --tprint (q)
        delete_mob_from_table_index(p)
        return
      end--if
      if string.lower(q[2])~= string.lower(cp_mobs[p].name) and #room_num_table > #cp_mobs  then
       delete_mob_from_table_index(p) -- not sure if this is working yet
       DebugNote ("If you see this message this was the function causing the stack overflow")
       elseif string.lower(q[2])~= string.lower(cp_mobs[p].name) and #room_num_table < #cp_mobs then
      DebugNote('room <cp_mobs and names dont match')
       buildRoomTable()
        return
      end--if
      if string.lower(q[2])~= string.lower(cp_mobs[p].name) and #room_num_table == #cp_mobs then
       DebugNote('room ==cp_mobs and names dont match')
       DebugNote(q[2].. " ".. cp_mobs[p].name)
        
          buildRoomTable()
         

        
      end--if
    end--for
  mob_index= 1
  var.cp_mobs = serialize.save( "cp_mobs", cp_mobs )
  phelper:broadcast(1, var.cp_mobs)
end

myThread= nil
local level = 0
local mylevel = 0
local oldlevel = 0
-- New initialization checks - Kobus
got_room = false
got_char = false
didonce = false



CPMobsLevelBound = nil
-- takes a level and makes a CPmobs table that is within 30 level of our current level
function CpMobsAbr(str)
  CPMobsLevelBound = nil
  levelAdj= 30
  levmin = tonumber(str)-levelAdj
  if levmin<0 then levmin=0 end
  levmax = tonumber(str)+levelAdj
  query = string.format("select * from CPMobs "..
    " where level between %s and %s "..
    "  order by  name, timeskilled desc", levmin,levmax)

  c = 0
  CPMobsLevelBound = db_query(dbkt, query)
  oldlevel = mylevel -- Won't rebuild until we level again - Kobus
end

room_num_table = {}

function clearTable()
  room_num_table= {}
  room_num_table2= {}
end

function makeTable(room_num, name, bool, isInTable, area, num)-- stores all names and room numbers into a global table
  room_num_table[counter]= {room_num, name, bool, isInTable, area, tonumber(num)}
  counter= counter + 1
-- tprint(room_num_table)
-- print(counter)

end
function makeTable2(room_num, name, bool, inTable, area)-- stores all names and room numbers into a global table
  room_num_table2[counter1]= {room_num, name, bool, inTable, area}
  counter1= counter1 + 1


end
--TODO: Change both prints to actually be something worth looking at.
function printTable() -- prints the global table for names and room numbers, used for debugging or quick checking
 if room_num_table ~= nil and #room_num_table>0 then
    ColourNote("Gray", "", "NUM  Mob name                             Dist   RoomId        Area")
    ColourNote("Gray", "", "------------------------------------------------------------------------");
    for i, row in pairs(cp_mobs) do
      print(string.format("%3d  %-35s  %-3s %-10s (%s) ", i, row.name,row.dist,room_num_table[i][1]  ,row.location))
    end
    ColourNote("Gray", "", "------------------------------------------------------------------------");
  DebugNote(cp_mobs)
  else
    print ("Nothing to print")
  end--if
end

function printTable1() -- prints the global table for names and room numbers, used for debugging or quick checking
 if room_num_table2 ~= nil and #room_num_table2>0 then
  tprint(room_num_table2)
  else
    print ("Nothing to print")
  end--if
end

curMob= ''
mobname= ''
word_count= tonumber(0)

function getTable(index) -- returns the first item in the table of room numbers, also makes a variable 'mobname' which is used for the autokill comand
    if room_num_table[index]== nil then
      return -1
    end
      local num =room_num_table[tonumber(index)][1]
      curMob= room_num_table[tonumber(index)][2]
    getName(index, 1)
    return num
end
-- Questioning why I am passing the num variable here... was this legacy?
function getName(index, num)
  local s= ''
  if cp_mobs== nil then
    print ("Use tcp before that command please")
    return
  end--if
  s = room_num_table[tonumber(index)][2] or curMob
 mobname = sanitizeName(s)
end

function sanitizeName(s)
local exit = 0
if s==nil then
  Note("s was nil")
  return
end
if check_CPMobs_Table()>0 then-- this needs to be reworked once all versions are unified. Aka when all versions have CPMobs support for Room CPs
  check_Keywords = string.format("SELECT keywords from CPMobs WHERE name= %s and keywords <> '';", fixsql(s))
    for _,keys in ipairs(db_query(dbkt,check_Keywords)) do
      DebugNote(keys)
      if keys.keywords ~= nil and keys.keywords ~= '' then
        return keys.keywords
      end
    end
end
  local s2= {}
  s =string.gsub(s, "-", " ")
  s =string.gsub(s, "'", " ")
  s =string.gsub(s, "%@r", " ")
  for i in s:gmatch( "%a+") do
    word_count = tonumber(word_count) + 1
    s2[word_count]= i
    s2[word_count]= string.gsub(s2[word_count] , ",", " ")
  end -- for
  word_count= 0
  if (s2[1] == "a" or s2[1] == "A" or s2[1] == "An" or s2[1] == "the" or s2[1] == "The" or s2[1] == "an") and table.getn(s2) >1 then
    if table.getn(s2)>2
    then
      s2[2]= string.sub(s2[2], 0, 3)
      s2[3] = string.sub(s2[#s2],0, 3)
      mobname = s2[2].." "..s2[3]
      else
      mobname = s2[2]
    end -- if
  else
  if table.getn(s2)>1
  then
    s2[1]= string.sub(s2[1], 0, 3)
    s2[2] = string.sub(s2[#s2],0, 3)
    mobname = s2[1].." "..s2[2]
  else
    mobname = s2[1]
  end--if
  end--if
    return mobname
end

function buildRoomTable()-- This sends the table to get room_ids
--local time1 = socket.gettime()*1000
  if cp_mobs ==nil then
      cp_mobs = mobsleft
  end
  counter = tonumber(1)
  counter1 = tonumber(1)
  FirstRun_cp_var = false
  clearTable()
  local roomCPCheck = 0
  for i,v in ipairs (cp_mobs) do
    getRoomId(cp_mobs[i].name, i )
  end
    
  for i,v in ipairs(room_num_table) do
    if (room_num_table[i][4]== false) then
      cp_mobs[i].intable = false
    else
      cp_mobs[i].intable = true
    end--if
  end --for
  DebugNote('==============================')
  sortRoomCPByPath()
  var.cp_mobs = serialize.save( "cp_mobs", cp_mobs )
  phelper:broadcast(1, var.cp_mobs)
end

local shortaname

function getRoomId(name, tableNum)-- Gets a roomId from campaign
local loc = cp_mobs[tableNum].location
dbA=GetInfo (66) ..'Aardwolf.db'
  
    local query1 = "select rooms.uid as room, rooms.name as roomName, rooms.area as area, areas.name as areaName, 'room' as type "..
        " from rooms rooms, areas "..
        " where areas.uid = rooms.area and "..
        " rooms.name = %s "..
        " union "..
        " SELECT rooms.uid as room, rooms.name as roomName, areas.uid as area, areas.name as areaName, 'area' as type" ..
        " FROM areas, rooms " ..
        " WHERE areas.name = %s and "..
        "rooms.area = areas.uid "..
        " ORDER BY type ASC "
    sql_now= string.format(query1, fixsql(loc), fixsql(loc) )
    -- print(sql_now)
    local count_check= 0
    local hld = {}
    for _,rows in ipairs(db_query(dbA,sql_now)) do
      table.insert(hld, rows)
    end -- for
    -- tprint(hld)
    if #hld == 0 then
        print(loc)
        print('this cp will be weird because of unmapped rooms.. all entries are subject TOL has broken')
    end
    for g, rows in pairs(hld) do
      -- this whole thing needs reworked... its a mess right now..
      if rows.type== 'room' then
        -- print(name)
        getRoomIdRoomCP(name,name, tableNum)
        
        return
      else
        getRoomIdAreaCP(name, tableNum)
        
      return
      end--if
    end
  end--if

sublist={1,1}


function getRoomIdAreaCP(name, tableNum)
    local nameHolder= nil
    local roomNumber= nil
    local roomTemp= nil
    local loc = cp_mobs[tableNum].location
    local found = false
    local time1 = socket.gettime()
    local thisrooms = rooms_tbl
    local thisareas = areas_tbl
    local timeskilled = 0
    local  cpmobquery = string.format("select  * "..
        "from CPMobs "..
        "where name like %s and "..
        "area_name = %s "..
        "ORDER by timeskilled desc ", fixsql(name), fixsql(loc))
    test_timeskileed = {}
    if CPMobsLevelBound ~= nil then
        for i, p in pairs(CPMobsLevelBound) do
            if name == p.name and loc == p.area_name and timeskilled<p.timeskilled then
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
        -- if found then 
        --   return
        -- end
    end
    if found == false then
        DebugNote("in query block")
        for _,a in ipairs(db_query(dbkt, cpmobquery)) do
         DebugNote(a)
            if found== false then
                DebugNote('the one I will use is: ')
                DebugNote (a)
                nameHolder = a.name
                roomNumber = a.room_id
                found = true
                table.insert(test_timeskileed, {a})
            end
        end
    end
    local count= 0
    if found == false then
        sublist={}
        for i, p in pairs(mobktbl) do
            if p.name == name then
                table.insert(sublist, {p.name, p.room_id, p.timeskilled})
            end
        end
      DebugNote("\n In second block ".. name.."\n")
        for i,a in pairs(sublist) do
            count = count+1
            DebugNote(a)
            DebugNote("-----")
            DebugNote('found is '.. tostring(found))
            nameHolder=a[1]
            roomTemp= tostring(a[2])
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
        end --for
    end --if
    if roomNumber ~= nil and nameHolder ~=nil then
        DebugNote ("check")
        DebugNote(cp_mobs[tableNum].num)
        DebugNote ("///check")
        makeTable(tonumber(roomNumber), nameHolder, cp_mobs[tableNum].mobdead, true, loc, cp_mobs[tableNum].num)
        mob_index= 1
    end--if
    if roomNumber == nil then
        DebugNote("here")
        makeTable(loc, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, false, loc, cp_mobs[tableNum].num)
        mob_index= 1
    end--if
    DebugNote("Times killed table")
    DebugNote(test_timeskileed)
    DebugNote("Times killed table === end")
end

function getRoomIdRoomCP(name, nameHolder, tableNum)-- TODO some bug here where it drops the last 2 things in list
    local loc = cp_mobs[tableNum].location
    local mob_table_name= ''
    local rows_counter= 1
    local rows_counter_check= 0
    local make1 = makeTable
    local make2 = makeTable2
    local call = CallPlugin
    local DebugNote = DebugNote
    local findmob_table= {}
    local area_table= {}
    local strbld = string.format
    local room_num_table= room_num_table
    local room_num_table2= room_num_table2
    local tableNum = tonumber(tableNum)
    local levelAdj = 11
    local found = 0
    local areaName
    local timeskilled = 0
    local roomNumber
    test_timeskileed = {}
    res, gmcparg = call("3e7dedbe37e44942dd46d264","gmcpval","char") --- We just want the gmcp.char section.
    luastmt = "gmcpdata = " .. gmcparg --- Convert the serialized string back into a lua table.
    assert (loadstring (luastmt or "")) ()
    level = tonumber(gmcpdata.status.level) -- uncomment for live
    if GQ_flag then levelAdj = 22 end
    --level = 70 -- for testing
    min_level = level - levelAdj
    max_level = level + levelAdj
    if CPMobsLevelBound ~= nil then
        for i, p in pairs(CPMobsLevelBound) do
            if name == p.name and loc == p.room_name and timeskilled<p.timeskilled then
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
            make1(roomNumber, name, cp_mobs[tableNum].mobdead, true, area_name, cp_mobs[tableNum].num) 
            DebugNote("Times killed table")
            DebugNote(test_timeskileed)
            DebugNote("Times killed table === end")
            return
        end
    end
    if (min_level<0)then min_level=0 end
    local queryCount = strbld("select COUNT(1) as counter"..
      " from rooms, areas"..
      " where areas.uid = rooms.area and rooms.name = %s",fixsql(cp_mobs[tableNum].location))
    local query1 = strbld("select rooms.uid as roomuid,"..
      " areas.name as areaName,"..
      " rooms.name as roomName"..
      " from rooms rooms, areas"..
      " where areas.uid = rooms.area and rooms.name = %s",fixsql(cp_mobs[tableNum].location))
    local  cpmobquery = string.format("select *"..
        "from CPMobs "..
        "where name like %s and "..
        "room_name = %s"..
        "ORDER by timeskilled asc ", fixsql(name), fixsql(loc))

    for _,rows in ipairs(db_query(dbkt, cpmobquery)) do
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
        make1(roomNumber, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, true, areaName, cp_mobs[tableNum].num)
        DebugNote("Times killed table")
        DebugNote(test_timeskileed)
        DebugNote("Times killed table === end")
        return
    end
    for _,rows in ipairs(db_query(dbA, queryCount)) do
        rows_counter = rows.counter
    end--for
    for _,rows in ipairs(db_query(dbA, query1)) do
        rows_counter_check = rows_counter_check+1
        area_table[rows_counter_check] = rows
    end--for
    local area_table_size = #area_table
    if areaLevel == nil then
        print('area table was nill when checking mobs, rebuilding...')
        areaLevel = db_query_area(dbkt, "select keyword, name, afrom, ato, alock from areas")
        print('Done rebuilding, moving forward...')
    end
    for z=1, area_table_size do
        roomNumber= tonumber(area_table[z].roomuid)
        DebugNote(areaLevel[area_table[z].areaName])
        if areaLevel[area_table[z].areaName].minLevel > max_level or areaLevel[area_table[z].areaName].maxLevel<min_level then 
            rows_counter= rows_counter-1
            rows_counter_check = rows_counter_check-1
        else
            local foundone_room_table2 = false
            local foundone_room_table = false
            if room_num_table ~= nil and #room_num_table >0 then
                for p= 1, #room_num_table do
                   if (string.lower(room_num_table[p][2]) == string.lower(nameHolder) or room_num_table[p][1]== area_table[z].uid)
                    and tableNum== tableNumHolder then foundone_room_table= true  end--if-- cp_mobs[tableNum].name
                end--for
            end--if
            if #room_num_table2 > 0 and room_num_table2 ~= nil then
                for i= 1, #room_num_table2 do
                    if area_table[z].areaName == room_num_table2[i][5] or room_num_table2[i][1]== area_table[z].roomuid  then-- see if the first condition needs and tableNum == tableNumHolder

                        foundone_room_table2 = true
                        break
                    else
                        foundone_room_table2 = false
                    end--if
                end--for
            end--if
            if not foundone_room_table then
                table.insert(test_timeskileed, {area_table[z]})
                make1(roomNumber, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, true, area_table[z].areaName, cp_mobs[tableNum].num)
                tableNumHolder= tonumber(tableNum)
                mob_index= 1
            elseif not foundone_room_table2 then
                make2(roomNumber, cp_mobs[tableNum].name, cp_mobs[tableNum].mobdead, true, area_table[z].areaName, cp_mobs[tableNum].num)
                mob_index= 1
            end--if
        end--for
    end--if
    tableNumHolder= tonumber(tableNum)
    mob_index= 1
    DebugNote("Times killed table")
    DebugNote(test_timeskileed)
    DebugNote("Times killed table === end")
end
room_not_in_database = {}


function sortRoomCPByPath()
  local x
  local room = -1
  dist_tbl = {}
  DebugNote('==============================')
  DebugNote(currentRoom.roomid)
  for i, p in ipairs(room_num_table) do
    DebugNote(i)
    DebugNote(p)
    x, dep = findpath(currentRoom.roomid,p[1])
    DebugNote('Depth:')
    DebugNote (dep)
    if dep ~= nil then
      table.insert(dist_tbl, { i, dep })
    else
      table.insert(dist_tbl, {i, 501})
    end--if
  end
  local keys = {}
  local b = {}
  local q = {}
  for k in pairs(dist_tbl) do table.insert(keys, k) end
  table.sort(keys, function(a, b) return dist_tbl[a][2] < dist_tbl[b][2] end)
  for _, k in ipairs(keys) do
    -- DebugNote('_ then k')
    -- DebugNote(_)
    -- DebugNote(k)
    -- DebugNote(k)
    -- DebugNote(dist_tbl[k][1])
    -- DebugNote(dist_tbl[k][2])
    cp_mobs[k].dist = dist_tbl[k][2]
    table.insert(b, cp_mobs[k])
    table.insert(q, room_num_table[k])
  end
  room_num_table = q
  cp_mobs = b

end

mob_index= tonumber(1)
mob_next_delete_value= nil

function do_Execute_no_echo(command)
  local original_echo_setting = GetOption("display_my_input")
  SetOption("display_my_input", 0)
  Execute(command)
  SetOption("display_my_input", original_echo_setting)
end

function gotoNextMob()-- This will goto the next mob, use with tcp
  if cp_mobs == nil then
    print ('Nothing to go to!')
    return
  end
  if mob_index == nil then
    mob_index=1
  end--if
  if room_num_table == nil or #room_num_table<1 then
    return
  end--if
  if room_num_table[1][1] == -1 then
    print ("Try tcpo or manually finding this mob.. use pto to check the other table")
    return
  end--if
  check_dead()
  if room_num_table[1][3] == false then
    if hunt_type(0, 0) == 1 then
      return
    end--if

    Execute('xmapper1 move '..  getTable(mob_index))
    DebugNote("Entry for mob_next_delete_value")
    DebugNote(mob_index)
    mob_next_delete_value= mob_index
    Send("sca ".. mobname)
  else
    if hunt_type(0, 1) == 1 then
      return
    end--if
    Execute('xmapper1 move '..  getTable(mob_index+1))
    DebugNote("Entry for mob_next_delete_value")
    DebugNote(mob_index+1)
    mob_next_delete_value= mob_index+1
    Send("sca ".. mobname)
  end--if
end

function gotoIndexMob(name, line, wildcards)-- This will goto the next mob, use with tcp
  print(wildcards[1])
  wild= tonumber(wildcards[1])
  if wild == nil then return end
  if cp_mobs == nil or #cp_mobs == 0 then
    print("Nothing to goto.")
    return
  end
  if room_num_table == nil  or #room_num_table == 0 then
    return
  end--if
  if tonumber(wildcards[1])<0 or tonumber(wildcards[1])> #room_num_table then
    wild = #room_num_table
  end
    if room_num_table[wild][1] == -1 then
    print ("Try tcpo or manually finding this mob.. use pto to check the other table")
    return
  end--if
  check_diff()
  check_dead()
    if hunt_type(wild, 0) == 1 then
      return
    end--if
    DebugNote("Entry for mob_next_delete_value")
    DebugNote(wild)
    mob_next_delete_value= wild
    Execute('xmapper1 move '..  getTable(tonumber(wild)))
    Send("sca ".. mobname)
end

function tcpohandler(name, line, wildcards)
  if wildcards[1] ~= nil then
    if room_num_table2 == nil or #room_num_table2 == 0 then
      print("nothing to print")
      return
    end--if
  end--if
  wild = tonumber(wildcards[1])
  if room_num_table2 == nil or #room_num_table2 == 0 then
    print('nothing to print')
    return
  end
  if tonumber(wildcards[1])>#room_num_table2 then
    wild = #room_num_table2
  end
  if #wildcards>=1 then
     mobname = sanitizeName(room_num_table2[tonumber(wild)][2])
    Execute ('xmapper1 move '.. room_num_table2[tonumber(wild)][1])
    DebugNote("Entry for mob_next_delete_value")
    DebugNote(wild)
    mob_next_delete_value= wild
    Send("sca ".. mobname)
  else
    mobname = sanitizeName(room_num_table2[1][2])
    Execute ('xmapper1 move '.. room_num_table2[1][1])
    mob_next_delete_value= 1
    Send("sca ".. mobname)
  end--if
end

function hunt_type (num, mob_id)
  if mob_index == 0 then
    local mob_index = 1
  else
    local mob_index = 2
  end--if
  if num ~= 0 then
    if type(room_num_table[tonumber(num)][1])== 'string' then -- If An index query and room type
      DebugNote("Entry for mob_next_delete_value")
    DebugNote(num)
      mob_next_delete_value= tonumber(num)
      holder= getTable(num)
      if (string.find(string.lower(room_num_table[num][1]), string.lower(areas_tbl[currentRoom.areaid].name))) then
        print('well this is awkward you are already in the correct area')
      else
        Execute('xrunto1 '..room_num_table[num][1])
      end--if
      cpn_script(tonumber(num))

      return 1
    end--if
  else
    if type(room_num_table[mob_index][1])== 'string' then-- if NOT an indexed query and a room type
      DebugNote("Entry for mob_next_delete_value")
    DebugNote(mob_index)
    mob_next_delete_value= mob_index
    holder= getTable(mob_index)
    if ( string.find(string.lower(room_num_table[mob_index][1]), string.lower(areas_tbl[currentRoom.areaid].name))) then
      print('well this is awkward you are in the correct area')
    else
      Execute('xrunto1 '..room_num_table[mob_index][1])
    end--if
    cpn_script(mob_index)

      return 1
    end--if
  end--if
end

where_mob= ''

function whereMob(name, line, wildcards)
  where_mob= wildcards[1]
  if where_mob==nil then
     if mobname ~= nil then
      EnableTrigger('where_mob_trig', true)
      Execute('where '.. mobname)

      DoAfterSpecial(2, "EnableTrigger('where_mob_trig', false)", 12)
    else
      print ("Need to use tcp or tcp <index> first")
      return
    end --if
  else
    EnableTrigger('where_mob_trig', true)
    Execute('where '.. where_mob)
    DoAfterSpecial(1, "EnableTrigger('where_mob_trig', false)", 12)
    where_mob = string.gsub(where_mob,"%d+%.","")
    mobname =  where_mob
  end--if
end

local where_black_list = {"Your magic is blessed with",
"You feel less righteous as the",
"You now possess magical powers",
"You feel gills growing on your",
"You now detect the presence of"}

where_trig_table = {}
WHERE_MOB = ''
function where_mob_trig(name, line, wildcards)
  dbA = GetInfo (66) ..'Aardwolf.db'
  for i,p in ipairs(where_black_list) do
    if (string.find( wildcards[0], p) ~= nil) then
      return
    end--if
  end--for
    wildcards[1], x = string.gsub(wildcards[1],"%.","")
    WHERE_MOB = trim(wildcards[1])
  bool = 0
  for word in mobname:gmatch("%w+") do
  if (string.find( string.lower(wildcards[1]), string.lower(word)) ~= nil) then
    bool =1
  end--if

  end -- for
  if bool == 1 then
    --Execute('mapper area '.. '"'..wildcards[2]..'"')
    if currentRoom == nil or table.getn(currentRoom) == 0 then
       res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264","gmcpval","room.info")
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
            fixsql(currentRoom.areaid), fixsql(wildcards[2]))
    -- print(qryArea)
    -- print("printing return val:")
    where_trig_table = db_query(dbA, qryArea)
    -- tprint(where_trig_table)
    -- print("printing return val:END ")
    -- print(currentRoom.areaid)
    -- print(wildcards[2])
    Execute('mapper goto ' .. where_trig_table[1].roomId)
    SendNoEcho('scan here')
    table.remove(where_trig_table, 1)
    --Execute('mapper next')
    EnableTrigger('where_mob_trig', false)
  end--if
end

function killMob()
  if mobname ~= nil then
    Execute("kill ".. mobname)
  else
    print ("Need to use tcp first")
  end --if
end



areaLevel= {}

-- In case of a mob not in the db then these will get used

count = 1
function incrementCounter()
count = count + 1
Execute("hunt ".. count..".".. mobname)
end

function reset_counter()
 count=1
end
CPMobs= {}
CPMobs1= {}
CPMobsIndex= 1
vnum_holder= 0
function reset_index()
 CPMobsIndex = 1
 CPMobs1= {}
end

cpn_is_room_type= false
cpn_is_room_type_table = {}
cpnrtt = 1



function hunt_from_link( area)
  DebugNote (area)
  Execute("xrunto1 ".. area)
  Execute ("hunt " .. mobname)
end

dbA = GetInfo (66) ..'Aardwolf.db'
dbkt=GetPluginInfo (GetPluginID (), 20) .. 'KillTable.db'
rooms_tbl = {1, 1}
areas_tbl = {}
mobktbl = {}




function StartScript()
    do_Execute_no_echo('map')
    do_Execute_no_echo("cp check")
    
    

    GetPageSize()
    SendNoEcho('tags scan on')
    areaLevel = db_query_area(dbkt, "select keyword, name, afrom, ato, alock from areas")
    print (GetPluginInfo (GetPluginID (), 20))
    qry= "select * from rooms where uid not like '*' and uid not like '**' order by uid"
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
   check_area_table()
   Clean_Kill_Table()
  -- Connected? GMCPHandler Enabled? Not initialized yet? Request the GMCP for initialization -Kobus
  if IsConnected() and GetPluginInfo("3e7dedbe37e44942dd46d264",17) and not didonce then
    Execute("sendgmcp request room")
    Execute("sendgmcp request char")
  end
end

function OnPluginBroadcast (msg, id, name, text)
    if (id == '3e7dedbe37e44942dd46d264') then
        if (text == "room.info") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264","gmcpval","room.info")
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
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264","gmcpval","char.status")
            luastmt = "gmcpdatacharstatus = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            char_status = gmcpdatacharstatus
            mylevel = tonumber(gmcpdatacharstatus.level)
        end
        if (text == "char.base") then
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264","gmcpval","char.base")
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
            res, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264","gmcpval","char.base")
            luastmt = "gmcpdatacharstatus = " .. gmcparg
            assert (loadstring (luastmt or "")) ()
            char_base= gmcpdatacharstatus
        end
        if got_room and got_char and not didonce then didonce = true print("start") StartScript() end -- Got what we needed from GMCP, initialize the TOL script -- Kobus
    end
end

function myHandler(udata, retries)
   DebugNote("BUSY!")
   return true
end
function OnPluginClose ()
    
end

function reset_cp_flag( )
  timeEnd()
  FirstRun_cp_var= true
end

function collectgarbagenow()
 --Note( collectgarbage("count")*1024)
  collectgarbage("collect")
  --Note( collectgarbage("count")*1024)
end

function DebugNote( msg )
  if not Debug then return end
    if type(msg)== 'table' then
      tprint(msg)
    else
      Note (msg)
    end

end

  -----------------------------------------------------------
  -- Scanning and highlighting
  -----------------------------------------------------------
function kill_scan_run()
    WHERE_MOB = ''
    where_trig_table = {}
    SCAN_TABLE = {}
end

function scan_table_handler()
  DebugNote(where_trig_table)
  DebugNote('where_trig_table '.. #where_trig_table)
  local found = false
  if #where_trig_table == 0 then
    return
  end
  query = string.format('select a.uid as areaid '..
          ' from rooms r '..
          ' join areas a '..
          ' on a.uid = r.area '..
          ' where r.uid = %i',
          where_trig_table[1].roomId)
  local areaid = db_query(dbA, query)
  DebugNote(areaid)
  DebugNote(currentRoom)
  if areaid[1].areaid ~= currentRoom.areaid then
    Note('looks like you are not in the same area, cancelling.')
    return
  end 
  for a=1,#SCAN_TABLE do
    for p=1, #SCAN_TABLE[a] do 
        -- print('scan table : ' .. SCAN_TABLE[a][p])
        -- print(WHERE_MOB)
        if string.lower(SCAN_TABLE[a][p]) == string.lower(WHERE_MOB) then
          found = true
          EnableTrigger('scan_nothing', 0)
          WHERE_MOB = ''
          where_trig_table = {}
          break  
        end
    end
  end

  SCAN_TABLE = {}
  if not found and #where_trig_table > 0 then
    
   -- print(#where_trig_table)
    --tprint(where_trig_table)
    EnableTrigger('scan_nothing', 1)
    scan_continue()
  end
end


ensure_room_change = -1
function scan_continue()
  if ensure_room_change == currentRoom.roomid then
    hunt_off()
    Note("You didn't move rooms, check your cexits and make sure the mob isn't in a maze")
  else
    ensure_room_change = currentRoom.roomid
  end
  if #where_trig_table >=1 then
      Execute('xmapper1 move '.. where_trig_table[1].roomId)
      SendNoEcho('scan here')
      table.remove(where_trig_table, 1)
    end
end

SCAN_TABLE = {}

function istarget(name, line, wildcards, style)
  local highlight = false
  local name = string.lower(wildcards[1])
  local target_mobs = { }
  if questHandler.mob ~= nil then target_mobs = { string.lower(questHandler.mob) } 
  end

  if #cp_mobs >= 1 then
    for a=1,#cp_mobs do table.insert(target_mobs, string.lower(cp_mobs[a].name)) 
    end
  end
  if #where_trig_table >= 1 then -- used for the wm and cpn commands
    table.insert(target_mobs, WHERE_MOB)-- the global mob name
    table.insert(SCAN_TABLE, wildcards)
  end
  for a=1,#target_mobs do
    if name == string.lower(target_mobs[a]) then
      highlight = true
      break
    end
  end
  for a,s in ipairs(style) do
    local text = RGBColourToName(s.textcolour)
    local back = RGBColourToName(s.backcolour)
    if highlight then text = "black" back = "yellow" end
    ColourTell(text,back,s.text)
  end
  if highlight then ColourTell("black","yellow"," [TARGET]") end
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
    mobname = sanitizeName(questHandler.mob)
  questHandler:gotoNext()
  end

  function qRooms()
    questHandler:showRooms()
  end

  function qRoomsAll()
    questHandler:showRooms(true)
  end

  function qTest()
    questHandler:setMob("the Liavango Despot")
    questHandler:setRoom("Home of the Despot")
    questHandler:setArea("The Darkside of the Fractured Lands")
  end