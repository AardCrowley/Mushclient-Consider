dofile(GetInfo(60) .. "aardwolf_colors.lua")
dofile(GetPluginInfo(GetPluginID(), 20) .. "Name_Cleanup.lua")

-- Options -----------------------------------------------
local BACKGROUND_COLOUR = ColourNameToRGB "black"
local BORDER_COLOUR = ColourNameToRGB "dimgray"
local DEFAULT_TEXT_COLOUR = ColourNameToRGB "white"
local TEXT_OFFSET = "4"
local BORDER_WIDTH = "1"
local LINE_SPACING = "1"
local FONT_NAME = "Dina"
local FONT_SIZE = 8
local WIN_STACK = "conw" -- Windows are stacked alphabetically, so a win named "aa" will sit on top of a win named "zz".
-- Adjust this setting to get the window to sit in front or behind other windows.
local SHOW_WELCOME = true
local TITLE = "consider all"
local ECHO_CONSIDER = false -- show consider in command window
local SHOW_NO_MOB = false -- show warning when considering an empty room
SHOW_FLAGS = true

local colour_to_ansi = {
    ["chartreuse"] = "@x118",
    ["darkviolet"] = "@x128",
    ["springgreen"] = "@x048",
    ["darkgoldenrod"] = "@x136",
    ["darkgreen"] = "@x022",
    ["lightpink"] = "@x217",
    ["darkmagenta"] = "@x090",
    ["tomato"] = "@x203",
    ["crimson"] = "@x125",
    ["forestgreen"] = "@x078",
    ["magenta"] = "@x201",
    ["gray"] = "@x008",
    ["gold"] = "@x220",
    ["white"] = "@x015",
    ["silver"] = "@x007"
}

require "aard_register_z_on_create"
require "mw_theme_base"
require "movewindow"
require "gmcphelper"
require "tprint"
require "var"
require "wait"

-- consider flags
local conw_on = tonumber(GetVariable("conw_on")) or 1
local conw_entry = tonumber(GetVariable("conw_entry")) or 1
local conw_kill = tonumber(GetVariable("conw_kill")) or 0
local conw_combatend = tonumber(GetVariable("conw_combatend")) or 1
local conw_misc = tonumber(GetVariable("conw_misc")) or 1
local conw_execute_mode = GetVariable("conw_execute_mode") ~= nil and GetVariable("conw_execute_mode") or "skill"
local conw_ignore_areas = {}

conwall_options = {}

local search_destroy_id = "e50b1d08a0cfc0ee9c442001"
local search_destroy_crowley_id = "30000000537461726c696e67"

local banner_height = 0
local currentState = -1
local keyword_position = GetVariable("keyword_position") or "endw"
local default_command

local mob_attack_sequence = 0
targT = {}

function ConwInfo(message)
    ColourTell("white", "blue", message)
    ColourNote("", "black", " ")
end

-- 1         At login screen, no player yet
-- 2         Player at MOTD or other login sequence
-- 3         Player fully active and able to receive MUD commands
-- 4         Player AFK
-- 5         Player in note
-- 6         Player in Building/Edit mode
-- 7         Player at paged output prompt
-- 8         Player in combat
-- 9         Player sleeping
-- 11        Player resting or sitting
-- 12        Player running

local was_in_combat = false
local sent_tags_option = false
function OnPluginBroadcast(msg, id, name, text)
    local gmcparg = ""
    local luastmt = ""

    if (currentState == -1) then
        currentState = 0 -- sent request
        Send_GMCP_Packet("request char")
    end

    -- Look for GMCP handler.
    if (id == '3e7dedbe37e44942dd46d264') then
        if (text == "char.status") then
            _, gmcparg = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char")
            luastmt = "gmcpdata = " .. gmcparg
            assert(loadstring(luastmt or ""))()
            currentState = tonumber(gmcpval("status.state"))
            Update_Current_Target()

            if not sent_tags_option and
                (currentState == 3 or currentState == 4 or currentState == 8 or currentState == 9 or currentState == 11 or
                    currentState == 12) then
                SendNoEcho("tags roomchars on")
                sent_tags_option = true
            end

            if currentState == 8 then
                was_in_combat = true
            elseif currentState == 3 and was_in_combat then
                was_in_combat = false
                if conw_on == 1 and conw_combatend == 1 then
                    Send_consider()
                end
            end

            --			DebugNote("char.status.state : " ..currentState)

        end
    end
end

function Keyword_change(name, line, wildcards)

    if keyword_position == "endw" then
        SetVariable("keyword_position", "beginning")
    else
        SetVariable("keyword_position", "endw")
    end
    keyword_position = GetVariable("keyword_position")

    ConwInfo("Keywords will now be taken from the " .. keyword_position .. " of Mobile names. ")
end -- keyword_position

local function toggle_flags()
    if SHOW_FLAGS == true then
        SHOW_FLAGS = false
        Note("You will no longer see the flags in the mini-window output")
    else
        SHOW_FLAGS = true
        Note("You will now see the flags in the mini-window output")
    end
end -- toggle_flags

function Conw(name, line, wildcards)

    -- show help <conw ?>
    if wildcards[1] == "?" or wildcards[1] == "help" then
        local comlist = {"conw - update window with consider all command.",
                         "<num> <word> - Execute <word> with keyword from line <num> on consider window.",
                         "<num> - Execute with default word.", "conw <word> - set default command.",
                         "conw IgnoreArea [add|remove|list] - add/remove or list area names to ignore for conw",
                         "  - For example: conw IgnoreArea add bootcamp - will skip auto sending consider command in Boot Training Grounds area",
                         "  -              conw IgnoreArea remove bootcamp - remove bootcamp from ignore list",
                         "  -              conw IgnoreArea list - list ignored areas",
                         "conw execute_mode [skill|cast|pro] - shows or sets how target keywords are passed to execute command",
                         "  - MUD server behaves differently when processing multiple keywords target for spells/skills.",
                         "  conw execute_mode skill - execute sends target as <num>.'keyword1 keyword2...'",
                         "  conw execute_mode cast - execute sends target as '<num>.keyword1 keyword2...'",
                         "  conw execute_mode pro - execute sends target as separate arguments without quotes, starting with <num> always.",
                         "  - An example for a 4th mob called 'Strong guard':",
                         "    skill - 4.'strong guard', use directly with skills or aliases like backstab* => backstab %1",
                         "    cast - '4.strong guard', use directly with spells or aliases like mm* => cast 'magic missile' %1",
                         "    pro   - 4 strong guard, use if you know what you're doing.",
                         "  - Note: target number is always present i.e.: 1 strong guard",
                         "conwall - Execute all targets matching selected options with default word.",
                         "conwall options - See current conwall options",
                         "  conwall options SkipEvil - toggle skip Evil mobs",
                         "  conwall options SkipGood - toggle skip Good mobs",
                         "  conwall options SkipNeutral - toggle skip Neutral mobs",
                         "  conwall options SkipSanctuary - toggle skip mobs with Sanctuary",
                         "  conwall options MinLevel <number> - skip mobs with level range lower than this number",
                         "    - For example: conwall options MinLevel -2 - will skips mobs with level range below -2",
                         "  conwall options MaxLevel <number> - skip mobs with level range higher than this number",
                         "    - For example: conwall options MaxLevel 21 - will skips mobs with level range above +21",
                         "  conwall options AoeCommand <command> - sets aoe command",
                         "  conwall options AoeMinCount <num> - minimum number of mobs to aoe a room",
                         "  conwall options AoeMaxCount <num> - maximum number of mobs to aoe a room",
                         "    -  set AoeMaxCount to -1, to disable aoe.",
                         "  conwall options MaxRoomCount <num> - maximum number of mobs to stack",
                         "conw_notify_attack <target> - use this alias if you're attacking mob via other commands but",
                         "    - want consider window to draw attack mark on that mob.",
                         "    - For example when using S&D's kk to attack do the following:",
                         "    - xset qk my_uber_attack_alias",
                         "    - and have the above alias expand to conw_notify_attack %1;;kill %1",
                         "conw auto|on|off - toggle auto update consider window on room entry and after combat.",
                         "conw misc|entry|kill|combatend - toggle consider on room entry, mob kill, combat end or miscellanous stuff",
                         "conw flags - toggle showing of flags on and off.", "conw ?|help - show this help."}
        for i, v in ipairs(comlist) do
            local sSpa = string.rep(" ", 20 - v:sub(1, v:find("-") - 1):len())
            ColourTell("yellow", GetInfo(271), v:sub(1, v:find("-") - 1) .. sSpa)
            ColourNote("white", GetInfo(271), v:sub(v:find("-"), v:len()))
        end
        return
    end

    if wildcards[1] == "auto" then
        if conw_on == 1 then
            conw_on = 0
            ConwInfo("Auto consider off.")
        else
            conw_on = 1
            ConwInfo("Auto consider on.")
        end
        ConfigureTriggers()
        Show_Window()
        return
    end

    if wildcards[1] == "off" then
        conw_on = 0
        ConfigureTriggers()
        ConwInfo("Auto consider off.")
        Show_Window()
        return
    end

    if wildcards[1] == "on" then
        conw_on = 1
        ConfigureTriggers()
        ConwInfo("Auto consider on.")
        Show_Window()
        return
    end

    if wildcards[1] == "kill" then
        if conw_kill == 1 then
            conw_kill = 0
            ConwInfo("Consider on kill - OFF.")
        else
            conw_kill = 1
            ConwInfo("Consider on kill - ON.")
        end
        if conw_on == 1 then
            EnableTriggerGroup("auto_consider_on_kill", conw_kill)
        end
        return
    end

    if wildcards[1] == "entry" then
        if conw_entry == 1 then
            conw_entry = 0
            ConwInfo("Consider on entry - OFF.")
        else
            conw_entry = 1
            ConwInfo("Consider on entry - ON.")
        end
        EnableTriggerGroup("auto_consider_on_entry", conw_entry)
        return
    end

    if wildcards[1] == "misc" then
        if conw_misc == 1 then
            conw_misc = 0
            ConwInfo("Consider on misc - OFF.")
        else
            conw_misc = 1
            ConwInfo("Consider on misc - ON.")
        end
        if conw_on == 1 then
            EnableTriggerGroup("auto_consider_misc", conw_misc)
        end
        return
    end

    if wildcards[1] == "combatend" then
        if conw_combatend == 1 then
            conw_combatend = 0
            ConwInfo("Consider on combat end - OFF.")
        else
            conw_combatend = 1
            ConwInfo("Consider on combat end - ON.")
        end
        return
    end

    if wildcards[1] == "chng" then
        Keyword_change()
        return
    end

    if wildcards[1] == "flags" then
        toggle_flags()
        return
    end

    if wildcards[1] and wildcards[1]:match("^execute_mode") then
        local new_mode = string.match(wildcards[1], "^execute_mode (%a+)$")
        if new_mode == "pro" then
            conw_execute_mode = "pro"
            SetVariable("conw_execute_mode", "pro")
        elseif new_mode == "skill" then
            conw_execute_mode = "skill"
            SetVariable("conw_execute_mode", "skill")
        elseif new_mode == "cast" then
            conw_execute_mode = "cast"
            SetVariable("conw_execute_mode", "cast")
        end
        Note("Conw execute_mode: " .. GetVariable("conw_execute_mode"))
    elseif wildcards[1] and wildcards[1]:match("^IgnoreArea add (.+)$") then
        local zone = string.match(wildcards[1], "^IgnoreArea add (.+)$")
        if conw_ignore_areas[zone] == nil then
            conw_ignore_areas[zone] = true
            SetVariable("conw_ignore_areas", serialize.save_simple(conw_ignore_areas))
            Note("Conw added " .. zone .. " to ignore areas list")
        else
            Note("Area " .. zone .. " is already in ignore areas list")
        end
    elseif wildcards[1] and wildcards[1]:match("^IgnoreArea remove (.+)$") then
        local zone = string.match(wildcards[1], "^IgnoreArea remove (.+)$")
        if conw_ignore_areas[zone] ~= nil then
            conw_ignore_areas[zone] = nil
            SetVariable("conw_ignore_areas", serialize.save_simple(conw_ignore_areas))
            Note("Conw removed " .. zone .. " from ignore areas list")
        else
            Note("Area " .. zone .. " is not in ignore areas list")
        end
    elseif wildcards[1] and wildcards[1]:match("^IgnoreArea list$") then
        Note("Conw ignoring the following areas:")
        tprint(conw_ignore_areas)
    elseif wildcards[1] and wildcards[1]:match("^%w+$") then
        SetVariable("default_command", wildcards[1])
        default_command = GetVariable("default_command")
        ConwInfo("Default command: " .. wildcards[1])
    end
end -- Conw

function Send_consider()
    if conw_on ~= 1 then
        return
    end

    if Is_in_ignored_zone() then
        local zone = gmcp("room.info.zone")
        targT = {}
        local t = {
            keyword = "",
            index = 1,
            name = "Ignoring zone " .. zone,
            mflags = "",
            line = "",
            colour = "gray",
            range = "",
            message = "",
            dead = false,
            attacked = false,
            aimed = false,
            left = false,
            came = false,
            pct = 100,
            attack_sequence = 0
        }
        table.insert(targT, t)
        Show_Window()
        return
    end

    local details = gmcp("room.info.details")
    if details:find("safe") then
        targT = {}
        local t = {
            keyword = "",
            index = 1,
            name = "Safe room",
            mflags = "",
            line = "",
            colour = "gray",
            range = "",
            message = "",
            dead = false,
            attacked = false,
            aimed = false,
            left = false,
            came = false,
            pct = 100,
            attack_sequence = 0
        }
        table.insert(targT, t)
        Show_Window()
        return
    end

    if GetVariable("doing_consider") == "true" then
        return
    else
        SetVariable("doing_consider", "true")
        SetVariable("waiting_for_consider_start", "true")
        EnableTriggerGroup("consider", true)
        SendNoEcho("consider all")
        SendNoEcho("echo nhm")
    end
end -- Send_consider

function Execute_Mob(command, index)
    wait.make(function()
        wait.time(0.01)
        local target
        if GetVariable("conw_execute_mode") == "pro" then
            target = tostring(targT[index].index) .. " " .. targT[index].keyword
        elseif GetVariable("conw_execute_mode") == "cast" then
            target = "'" .. tostring(targT[index].index) .. "." .. targT[index].keyword .. "'"
        else
            target = tostring(targT[index].index) .. ".'" .. targT[index].keyword .. "'"
        end
        mob_attack_sequence = mob_attack_sequence + 1
        targT[index].attack_sequence = mob_attack_sequence
        ConwInfo(command .. " " .. target)
        Execute(command .. " " .. target)
    end)
end

function Execute_command(id, s)
    if not s then
        return
    end
    s = s:match("^([%d.%w' ]+)%:%d+$")
    Execute(default_command .. " " .. s)
    ConwInfo(default_command .. " " .. s)
end -- Execute_command

function Command_line(name, line, wildcards)
    local iNum = tonumber(wildcards[1])
    local sKey = ""

    if iNum > #targT then
        return
    end

    if wildcards[2] == "" then
        sKey = default_command
    else
        sKey = tostring(wildcards[2])
    end

    if targT[iNum] then
        targT[iNum].attacked = true
        Execute_Mob(sKey, iNum)
    else
        ConwInfo("no target in targT ")
    end

end -- Command_line

function ShouldSkipMob(mob, show_messages)
    local minlevel, maxlevel = string.match(mob.range, "([+-]?%d+) to ([+-]?%d+)")
    if not minlevel or not maxlevel then
        if string.match(mob.range, "%-20 and below") then
            minlevel = -300
            maxlevel = -20
        elseif string.match(mob.range, "%+51 and above") then
            minlevel = 50
            maxlevel = 300
        else
            minlevel = -300
            maxlevel = 300
        end
    else
        minlevel = tonumber(minlevel)
        maxlevel = tonumber(maxlevel)
        if minlevel > maxlevel then
            minlevel, maxlevel = maxlevel, minlevel
        end
    end

    if mob.left or mob.came then
        if show_messages then
            ConwInfo("Skipping moved " .. mob.keyword .. " ")
        end
    elseif mob.attacked then
        if show_messages then
            ConwInfo("Skipping already attacked " .. mob.keyword .. " ")
        end
    elseif mob.dead then
        if show_messages then
            ConwInfo("Skipping already dead " .. mob.keyword .. " ")
        end
    elseif conwall_options.skip_evil and (mob.mflags:match("%(R%)") or mob.mflags:match("%(red aura%)")) then
        if show_messages then
            ConwInfo("Skipping EVIL " .. mob.keyword .. " ")
        end
    elseif conwall_options.skip_good and (mob.mflags:match("%(G%)") or mob.mflags:match("%(golden aura%)")) then
        if show_messages then
            ConwInfo("Skipping GOOD " .. mob.keyword .. " ")
        end
    elseif conwall_options.skip_neutral and not (mob.mflags:match("%(R%)") or mob.mflags:match("%(red aura%)")) and
        not (mob.mflags:match("%(G%)") or mob.mflags:match("%(golden aura%)")) then
        if show_messages then
            ConwInfo("Skipping NEUTRAL " .. mob.keyword .. " ")
        end
    elseif conwall_options.skip_sanctuary and (mob.mflags:match("%(W%)") or mob.mflags:match("%(white aura%)")) then
        if show_messages then
            ConwInfo("Skipping SANCTUARY " .. mob.keyword .. " ")
        end
    elseif minlevel < conwall_options.min_level or maxlevel > conwall_options.max_level then
        if show_messages then
            ConwInfo("Skipping out of level range " .. mob.keyword .. " ")
        end
    else
        return false
    end
    return true
end

function Conw_all(name, line, wildcards)
    if #targT == 0 then
        ConwInfo("no targets to conwall")
        return
    end

    local isUnlimitedAoe = tostring(conwall_options.max_aoe_count) == "-1"
    local minAoeCount = conwall_options.min_aoe_count
    local maxAoeCount = conwall_options.max_aoe_count
    local maxRoomCount = conwall_options.max_room_count
    local foundCount = 0
    local firstFoundIndex = nil

    -- Pre-calculate condition to determine if we will use AOE or single target based on min and max count
    local willUseAoe = false

    -- Determine foundCount, firstFoundIndex and if we will use AOE
    for i = #targT, 1, -1 do
        if not ShouldSkipMob(targT[i], isUnlimitedAoe) then
            foundCount = foundCount + 1
            firstFoundIndex = firstFoundIndex or i
        end
    end

    -- Determine if AOE should be used based on found targets and options
    willUseAoe = foundCount == #targT and foundCount >= minAoeCount and foundCount <= maxAoeCount

    -- Execute commands based on AOE or single target strategy
    if isUnlimitedAoe then
        targTEnd = foundCount <= maxRoomCount and foundCount or maxRoomCount
        for i = targTEnd, 1, -1 do
            if not ShouldSkipMob(targT[i], true) then
                targT[i].attacked = true
                Execute_Mob(default_command, i)
            end
        end
    elseif willUseAoe then
        for i = #targT, 1, -1 do
            targT[i].attacked = true
        end
        Execute(conwall_options.aoe_command)
        Execute(default_command)
    elseif firstFoundIndex then
        targT[firstFoundIndex].attacked = true
        Execute_Mob(default_command, firstFoundIndex)
    end

    Show_Window()
end

-- Taken from http://stackoverflow.com/questions/15706270/sort-a-table-in-lua
function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

function FinbMobTargetSortFunction(t, a, b)
    local a_attacked = t[a].attacked and 1 or 0
    local b_attacked = t[b].attacked and 1 or 0
    if t[a].pct ~= t[b].pct then
        return t[a].pct < t[b].pct
    end
    if a_attacked ~= b_attacked then
        return a_attacked > b_attacked
    end
    if t[a].attack_sequence ~= t[b].attack_sequence then
        return t[a].attack_sequence < t[b].attack_sequence
    end
    return a < b
end

function Update_kill(name, line, wildcards)
    -- Note("KILL!!!!! ["..wildcards[1].."]")

    local trigger_name = wildcards[1]:gsub("^%u", string.lower)

    for k, v in spairs(targT, FinbMobTargetSortFunction) do
        -- Lower case first character as it's done in some death messages like kills with "project force" etc.
        local list_name = v.name:gsub("^%u", string.lower)
        if not v.dead and (trigger_name:sub(1, #v.name) == list_name) then
            v.dead = true
            v.mflags = " dead "
            v.pct = 0
            Update_mobs_indicies(k + 1)
            Show_Window()
            break
        end
    end
end

function Update_mobs_indicies(from)
    for i = #targT, from, -1 do
        local count = 1
        for j = i - 1, 1, -1 do
            if targT[i].name == targT[j].name and not (targT[j].dead or targT[j].left) then
                count = count + 1
            end
        end
        targT[i].index = count
    end
end

function Is_in_ignored_zone()
    local zone = gmcp("room.info.zone")
    return conw_ignore_areas[zone] ~= nil
end

function Update_mob_came(name, line, wildcards)
    -- Note("CAME!!!!! ["..wildcards[1].."]")

    if Is_in_ignored_zone() then
        return
    end

    local mob = wildcards[1]
    if mob == nil then
        return
    end
    local flags = SHOW_FLAGS and " came " or "      "

    local t = {
        keyword = GetKeyword(mob),
        index = 1,
        name = mob,
        mflags = flags,
        line = line,
        colour = "gray",
        range = "(???)",
        message = line,
        dead = false,
        attacked = false,
        aimed = false,
        left = false,
        came = true,
        pct = 100,
        attack_sequence = 0
    }

    table.insert(targT, 1, t)
    Update_mobs_indicies(2)
    Show_Window()
end

function Update_mob_left(name, line, wildcards)
    -- Note("LEFT!!!!! ["..wildcards[1].."]")

    if Is_in_ignored_zone() then
        return
    end

    local mob = wildcards[1]
    if mob == nil then
        return
    end
    local flags = SHOW_FLAGS and " left " or "      "

    -- Check if there's a mob with same name which recently came to the room
    for k, v in ipairs(targT) do
        if v.name == mob and v.came and not v.left and not v.dead then
            table.remove(targT, k)
            Update_mobs_indicies(k)
            Show_Window()
            return
        end
    end

    -- Try to find alive not attacked mob first in case there're difference mobs with the same name
    for i = #targT, 1, -1 do
        if not targT[i].attacked and not targT[i].dead and not targT[i].left and targT[i].name == mob then
            targT[i].left = true
            targT[i].mflags = flags
            Update_mobs_indicies(i)
            Show_Window()
            return
        end
    end

    -- Fallback to check any mob with given name
    for i = #targT, 1, -1 do
        if not targT[i].dead and not targT[i].left and targT[i].name == mob then
            targT[i].left = true
            targT[i].mflags = flags
            Update_mobs_indicies(i)
            Show_Window()
            break
        end
    end
end

local roomchars
function RoomCharsStart(name, line, wildcards)
    roomchars = {}
    EnableTriggerGroup("roomchars", 1)
end

function CaptureRoomChar(name, line, wildcards)
    table.insert(roomchars, line)
end

function RoomCharsEnd(name, line, wildcards)
    EnableTriggerGroup("roomchars", 0)

    if conw_entry == 1 then
        if #roomchars > 0 then
            Send_consider()
        else
            targT = {}
            Show_Window()
        end
    end
end

-- Call this if you're attacking mob yourself but still want a nice "x" mark in the window to appear.
function Notify_Attack(name, line, wildcards)
    local mob = wildcards[1]
    local mob_num = tonumber(mob:match("^'?(%d+)%.")) or 1
    local mob_stripped = mob:gsub("^'?%d*%.?'?", ""):gsub("'$", "")
    local found = false
    for i = #targT, 1, -1 do
        if targT[i].index == mob_num and targT[i].keyword == mob_stripped then
            targT[i].attacked = true
            Show_Window()
            found = true
            break
        end

        -- S&D have random() calls when deciding how many characters to use from each of word of mob keywords...
        -- see if all words in attack command and mob kws are substrings of one another
        -- Check if mob and target numbers match first, then compare the words
        if mob_num == targT[i].index then
            local target_stripped = targT[i].keyword
            local targ_words = target_stripped:lower():gmatch("%S+")
            local match = true
            for word in mob_stripped:lower():gmatch("%S+") do
                local target = targ_words()
                if target == nil or not (word:sub(1, #target) == target or target:sub(1, #word) == word) then
                    match = false
                    break
                end
            end
            if match and targ_words() == nil then
                targT[i].attacked = true
                Show_Window()
                found = true
                break
            end
        end
    end

    if not found then
        Note("can't find target: " .. mob)
        Note("mobs in room:")
        for i = #targT, 1, -1 do
            Note(tostring(i) .. ". " .. tostring(targT[i].index) .. " " .. targT[i].keyword)
        end
    end
end

function Default_conwall_options()
    local default_options = {
        skip_evil = false,
        skip_good = false,
        skip_neutral = false,
        skip_sanctuary = false,
        min_level = -2,
        max_level = 20,
        aoe_command = "c ultrablast",
        min_aoe_count = 5,
        max_aoe_count = -1,
        max_room_count = 5,
    }
    return default_options
end

function Check_conwall_options()
    if conwall_options.min_level == nil then
        conwall_options.min_level = Default_conwall_options().min_level
    end
    if conwall_options.max_level == nil then
        conwall_options.max_level = Default_conwall_options().max_level
    end
    if conwall_options.skip_neutral == nil then
        conwall_options.skip_neutral = Default_conwall_options().skip_neutral
    end
    if conwall_options.aoe_command == nil then
        conwall_options.aoe_command = Default_conwall_options().aoe_command
    end
    if conwall_options.min_aoe_count == nil then
        conwall_options.min_aoe_count = Default_conwall_options().min_aoe_count
    end
    if conwall_options.max_aoe_count == nil then
        conwall_options.max_aoe_count = Default_conwall_options().max_aoe_count
    end
    if conwall_options.max_room_count == nil then
        conwall_options.max_room_count = Default_conwall_options().max_room_count
    end
end

function Load_conwall_options()
    conwall_options = loadstring(string.format("return %s",
        var.config or serialize.save_simple(Default_conwall_options())))()
    Check_conwall_options()
    Save_conwall_options()
end

function Get_conwall_options()
    return serialize.save_simple(conwall_options)
end

function Save_conwall_options()
    var.config = Get_conwall_options()
end

function ShowNote(str)
    AnsiNote(stylesToANSI(ColoursToStyles(string.format("@w%s@w", str))))
end

function Conw_all_options(name, line, wildcards)
    if wildcards[1] == "" then
        Note("Current conwall options:")
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipEvil", conwall_options.skip_evil and "@GYes" or "@RNo"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipGood", conwall_options.skip_good and "@GYes" or "@RNo"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipNeutral",
            conwall_options.skip_neutral and "@GYes" or "@RNo"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipSanctuary",
            conwall_options.skip_sanctuary and "@GYes" or "@RNo"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "MinLevel", tostring(conwall_options.min_level)))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "MaxLevel", tostring(conwall_options.max_level)))
        ShowNote(string.format("  @Y%-13.13s @w(%s@w)", "AoeCommand", conwall_options.aoe_command))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "AoeMinCount", tostring(conwall_options.min_aoe_count)))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "AoeMaxCount", tostring(conwall_options.max_aoe_count)))
    elseif wildcards[1] == " SkipEvil" then
        Note("Changed conwall option:")
        conwall_options.skip_evil = not conwall_options.skip_evil
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipEvil", conwall_options.skip_evil and "@GYes" or "@RNo"))
        Show_Window()
        Save_conwall_options()
    elseif wildcards[1] == " SkipGood" then
        Note("Changed conwall option:")
        conwall_options.skip_good = not conwall_options.skip_good
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipGood", conwall_options.skip_good and "@GYes" or "@RNo"))
        Show_Window()
        Save_conwall_options()
    elseif wildcards[1] == " SkipNeutral" then
        Note("Changed conwall option:")
        conwall_options.skip_neutral = not conwall_options.skip_neutral
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipNeutral",
            conwall_options.skip_neutral and "@GYes" or "@RNo"))
        Show_Window()
        Save_conwall_options()
    elseif wildcards[1] == " SkipSanctuary" then
        Note("Changed conwall option:")
        conwall_options.skip_sanctuary = not conwall_options.skip_sanctuary
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "SkipSanctuary",
            conwall_options.skip_sanctuary and "@GYes" or "@RNo"))
        Show_Window()
        Save_conwall_options()
    elseif string.match(wildcards[1], " MinLevel %-?%d+") then
        Note("Changed conwall option:")
        conwall_options.min_level = tonumber(string.match(wildcards[1], " MinLevel (%-?%d+)"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "MinLevel", tostring(conwall_options.min_level)))
        Show_Window()
        Save_conwall_options()
    elseif string.match(wildcards[1], " MaxLevel %-?%d+") then
        Note("Changed conwall option:")
        conwall_options.max_level = tonumber(string.match(wildcards[1], " MaxLevel (%-?%d+)"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "MaxLevel", tostring(conwall_options.max_level)))
        Show_Window()
        Save_conwall_options()
    elseif wildcards[1]:match("AoeCommand (.+)") then
        Note("Changed conwall option:")
        conwall_options.aoe_command = wildcards[1]:match("AoeCommand (.+)")
        ShowNote(string.format("  @Y%-13.13s @w(%s@w)", "AoeCommand", conwall_options.aoe_command))
        Save_conwall_options()
    elseif string.match(wildcards[1], " AoeMinCount %-?%d+") then
        Note("Changed conwall option:")
        conwall_options.min_aoe_count = tonumber(wildcards[1]:match("AoeMinCount (%-?%d+)"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "AoeMinCount", tostring(conwall_options.min_aoe_count)))
        Save_conwall_options()
    elseif string.match(wildcards[1], " AoeMaxCount %-?%d+") then
        Note("Changed conwall option:")
        conwall_options.max_aoe_count = tonumber(wildcards[1]:match("AoeMaxCount (%-?%d+)"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "AoeMaxCount", tostring(conwall_options.max_aoe_count)))
        Save_conwall_options()
    elseif string.match(wildcards[1], " MaxRoomCount %-?%d+") then
        Note("Changed conwall option:")
        conwall_options.max_room_count = tonumber(wildcards[1]:match("MaxRoomCount (%-?%d+)"))
        ShowNote(string.format("  @Y%-13.13s @w(%-3.5s@w)", "MaxRoomCount", tostring(conwall_options.max_room_count)))
        Save_conwall_options()
    else
        Note("Unknown conwall command!")
    end
end

function GetKeyword(mob)
    local nameCount = 1
    for i, mobInfo in pairs(targT) do
        if mobInfo.name == mob then
            nameCount = nameCount + 1
        end
    end

    if (GetPluginInfo(search_destroy_id, 17)) then
        local gmcproomdata = gmcp("room")
        if gmcproomdata ~= nil and gmcproomdata.info ~= nil then
            local _, oldmob = CallPlugin(search_destroy_id, "get_short_mob_name")
            _, mob, _ = CallPlugin(search_destroy_id, "IGuessMobNameNoBroadcast", mob, gmcproomdata.info.zone)
            CallPlugin(search_destroy_id, "set_short_mob_name", oldmob)
        else
            mob = Stripname(mob)
        end
    elseif (GetPluginInfo(search_destroy_crowley_id, 17)) then
        local gmcproomdata = gmcp("room")
        if gmcproomdata ~= nil and gmcproomdata.info ~= nil then
            _, mob = CallPlugin(search_destroy_crowley_id, "gmkw", mob, gmcproomdata.info.zone)
        else
            mob = Stripname(mob)
        end
    else
        mob = Stripname(mob)
    end

    return mob, nameCount
end

function Process_flags(flags)
    local newflags = ''
    if string.find(flags, "%(W%)") or string.find(flags, "%(White Aura%)") then
        newflags = newflags .. "@x015(W)"
    else
        newflags = newflags .. "   "
    end
    if string.find(flags, "%(R%)") or string.find(flags, "%(Red Aura%)") then
        newflags = newflags .. "@x001(R)"
    elseif string.find(flags, "%(G%)") or string.find(flags, "%(Golden Aura%)") then
        newflags = newflags .. "@x003(G)"
    else
        newflags = newflags .. "   "
    end

    return newflags
end

function Adapt_consider(name, line, wildcards)
    if GetVariable("waiting_for_consider_start") == "true" then
        SetVariable("waiting_for_consider_start", "false")
        targT = {}
        mob_attack_sequence = 0
    end

    local flags = nil
    if SHOW_FLAGS then -- we want to be able to show the flags to the user - Shindo
        flags = Process_flags(wildcards[1])
    else
        flags = ""
    end
    local mob = nil
    mob = wildcards[2] -- New version because of regex triggers - Kobus

    -- Removed for loop here, no longer necessary with color, range set by triggers - Kobus
    if mob then
        local keyword, index
        keyword, index = GetKeyword(mob)
        local t = {
            keyword = keyword,
            index = index,
            name = mob,
            mflags = flags,
            line = line,
            colour = mob_color,
            range = "(" .. mob_range .. ")",
            message = line,
            dead = false,
            attacked = false,
            aimed = false,
            left = false,
            came = false,
            pct = 100,
            attack_sequence = 0
        } -- Changed to use color, range set by triggers - Kobus
        -- Note("added ".. tostring(t.index).. ".".. tostring(t.keyword))
        if ECHO_CONSIDER then
            -- ColourTell   --build the string in parts
            ColourNote(mob_color, "", line .. " (" .. mob_range .. ")")
            -- Changed to use color, range set by triggers - Kobus
        end
        table.insert(targT, t)
    end -- if

    if not mob and SHOW_NO_MOB then
        ConwInfo("Could not find anything: " .. line)
    end -- not  found in table

end -- Adapt_consider

function Draw_Title()
    local consider_status = ""
    local title_text = ""
    local entrycheck = {"@RE", "@GE"}
    local killcheck = {"@RK", "@GK"}
    local misccheck = {"@RM", "@GM"}
    local combatendcheck = {"@RC@W", "@GC@W"}
    local skipevil = {"@GR@W", "@RR@W"}
    local skipgood = {"@GG@W", "@RG@W"}
    local skipneut = {"@GN@W", "@RN@W"}
    local skipsanc = {"@GW@W", "@RW@W"}

    -- draw the title and add drag hotspot
    local top = BORDER_WIDTH + LINE_SPACING
    local bottom = top + Font_height
    local left = BORDER_WIDTH + TEXT_OFFSET
    local right = WindowInfo(Win, 3)

    movewindow.add_drag_handler(Win, 0, top, right, bottom, 1)
    if (conw_on == 1) then
        consider_status = "@GON@W " .. entrycheck[conw_entry + 1] .. killcheck[conw_kill + 1] ..
                              misccheck[conw_misc + 1] .. combatendcheck[conw_combatend + 1] .. " " ..
                              skipevil[(conwall_options.skip_evil and 1 or 0) + 1] ..
                              skipgood[(conwall_options.skip_good and 1 or 0) + 1] ..
                              skipneut[(conwall_options.skip_neutral and 1 or 0) + 1] ..
                              skipsanc[(conwall_options.skip_sanctuary and 1 or 0) + 1] .. " " ..
                              string.format("%+d", conwall_options.min_level) .. ".." ..
                              string.format("%+d", conwall_options.max_level)
    else
        consider_status = "@ROFF@W"
    end
    title_text = ColoursToStyles(string.format("@W%s (%s) - %s", TITLE, default_command, consider_status))
    Theme.WindowTextFromStyles(Win, Font_id, title_text, left, top, right, bottom, utf8)

    -- draw drag bar rectangle
    WindowRectOp(Win, 1, 0, 0, WindowInfo(Win, 3), WindowInfo(Win, 4), BORDER_COLOUR)

    banner_height = bottom + LINE_SPACING + BORDER_WIDTH

end -- MakeTitle

function Consider_end()
    if GetVariable("waiting_for_consider_start") == "true" then
        SetVariable("waiting_for_consider_start", "false")
        targT = {}
    end
    Show_Window()
    SetVariable("doing_consider", "false")
    EnableTriggerGroup("consider", false)
end -- Consider_end

function Update_Current_Target()
    local target = gmcp("char.status.enemy")
    if target == nil or target == "" then
        return
    end
    target = strip_colours(target:lower())

    for i = #targT, 1, -1 do
        targT[i].aimed = false
    end
    local found = false
    for k, v in spairs(targT, FinbMobTargetSortFunction) do
        if not v.dead and not v.left and v.name:lower() == target then
            v.aimed = true
            v.pct = tonumber(gmcp("char.status.enemypct")) or 100
            found = true
            break
        end
    end
    Show_Window()
end

function Show_Window()
    -- get width and height and draw the window
    if #targT > 0 then
        for i, v in ipairs(targT) do
            Window_width = math.max((WindowTextWidth(Win, Font_id, tostring(i) .. ".   " .. strip_colours(v.mflags) ..
                " " .. v.name .. " " .. v.range) + TEXT_OFFSET * 2 + BORDER_WIDTH * 2), Banner_width, Window_width)
        end
    else
        Window_width = Banner_width
    end
    Window_height = banner_height * 1.2 + #targT * (Font_height + LINE_SPACING)

    WindowCreate(Win, Windowinfo.window_left, Windowinfo.window_top, Window_width, -- width
    Window_height, -- height
    Windowinfo.window_mode, Windowinfo.window_flags, BACKGROUND_COLOUR)

    -- draw each line
    local top = banner_height + LINE_SPACING
    local left = TEXT_OFFSET + BORDER_WIDTH
    local right = 0
    local bottom = top + Font_height

    for i, v in ipairs(targT) do
        local fontid;
        fontid = (v.dead or v.left) and FontStrikeout_id or
                     ((v.aimed or not ShouldSkipMob(v, false)) and FontBold_id or Font_id)
        local sAttacked = (v.aimed and not v.dead) and "@R\215@W " or (v.attacked and "@G\215@W " or "  ")
        local sLine = tostring(i) .. ". " .. sAttacked .. v.mflags .. " @W"
        local name_left = WindowTextWidth(Win, fontid, strip_colours(sLine)) + left
        sLine = sLine .. v.name .. " " .. colour_to_ansi[v.colour] .. v.range
        right = WindowTextWidth(Win, fontid, strip_colours(sLine)) + left
        if v.pct ~= nil then
            local pct = tonumber(v.pct)
            if pct ~= nil and pct < 100 then
                local name_len = #strip_colours(v.name)
                Theme.DrawTextBox(Win, fontid, name_left, top, string.rep(" ", math.ceil((100 - pct) * name_len / 100)),
                    utf8, false, 121, 0)
            end
        end
        Theme.WindowTextFromStyles(Win, fontid, ColoursToStyles(sLine), left, top, right, bottom, utf8)
        local sBalloon = v.line .. " " .. v.range .. "\n\n" .. "Click to Execute: '" .. default_command .. " " ..
                             tostring(v.index) .. "." .. v.keyword .. "'"
        WindowAddHotspot(Win, v.index .. "." .. v.keyword .. ":" .. tostring(i), left, top, right, bottom, "", -- MouseOver
            "", -- CancelMouseOver
            "", -- MouseDown
            "", -- CancelMouseDown
            "Execute_command", -- MouseUp
            sBalloon, 1, -- Cursor
            0) --  Flag
        top = bottom + LINE_SPACING
        bottom = top + Font_height -- ]]
    end

    -- draw the title
    Draw_Title()

    WindowShow(Win, true)
end -- Show_Consider

function Show_Banner()

    Window_width = Title_width + BORDER_WIDTH * 2 + TEXT_OFFSET * 2
    Window_height = Font_height + LINE_SPACING * 2 + Descent

    WindowCreate(Win, Windowinfo.window_left, Windowinfo.window_top, Window_width, -- width
    Window_height, -- height
    Windowinfo.window_mode, Windowinfo.window_flags, BACKGROUND_COLOUR)

    Draw_Title()

    WindowShow(Win, true)

end -- ShowBanner

function MouseUp(flags, hotspot_id, win)
    if bit.band(flags, miniwin.hotspot_got_rh_mouse) ~= 0 then
        Right_click_menu()
    end
    return true
end

function Right_click_menu()
    Menustring = "!Bring to Front|Send to Back"
    Result = WindowMenu(Win, WindowInfo(Win, 14), WindowInfo(Win, 15), Menustring)
    if Result ~= "" then
        local numResult = tonumber(Result)
        if numResult == 1 then
            -- bring to front
            CallPlugin("462b665ecb569efbf261422f", "boostMe", Win)
            -- Note("Front")
        elseif numResult == 2 then
            -- send to back
            CallPlugin("462b665ecb569efbf261422f", "dropMe", Win)
            -- Note("Back")
        end
    end
end

function ConfigureTriggers()
    if conw_on == 1 then
        EnableTriggerGroup("auto_consider_on_kill", conw_kill)
        EnableTriggerGroup("auto_consider_on_entry", conw_entry)
        EnableTriggerGroup("auto_consider_misc", conw_misc)
        EnableTriggerGroup("auto_track_kills", 1)
        EnableTriggerGroup("track_mob_moves", 1)
    else
        EnableTriggerGroup("auto_consider_on_kill", 0)
        EnableTriggerGroup("auto_consider_on_entry", 0)
        EnableTriggerGroup("auto_consider_misc", 0)
        EnableTriggerGroup("auto_track_kills", 0)
        EnableTriggerGroup("track_mob_moves", 0)
    end
end

function OnPluginInstall()

    if SHOW_WELCOME then
        Note("Consider_Window.xml installed")
        -- Suggest help command - Kobus
        Note("For a list of commands type 'conw ?'")
    end

    Win = WIN_STACK .. GetPluginID()

    local fonts = utils.getfontfamilies()
    if fonts[FONT_NAME] then
        Font_size = FONT_SIZE
        Font_name = FONT_NAME
    elseif fonts.Dina then
        Font_size = 8
        Font_name = "Dina" -- the actual font
    else
        Font_size = 10
        Font_name = "Courier"
    end -- if

    Font_id = "consider_font"
    FontStrikeout_id = "consider_strikeout_font"
    FontBold_id = "consider_bold_font"

    Windowinfo = movewindow.install(Win, 6, miniwin.create_absolute_location)

    check(WindowCreate(Win, Windowinfo.window_left, Windowinfo.window_top, 1, 1, Windowinfo.window_mode,
        Windowinfo.window_flags, BACKGROUND_COLOUR))

    WindowFont(Win, Font_id, Font_name, Font_size, false, false, false, false, 0, 0) -- normal
    Font_height = WindowFontInfo(Win, Font_id, 1) -- height
    Ascent = WindowFontInfo(Win, Font_id, 2)
    Descent = WindowFontInfo(Win, Font_id, 3)

    WindowFont(Win, FontStrikeout_id, Font_name, Font_size, false, false, false, true, 0, 0) -- strikeout
    WindowFont(Win, FontBold_id, Font_name, Font_size, true, false, false, false, 0, 0) -- bold

    default_command = GetVariable("default_command") or "kill"
    keyword_position = GetVariable("keyword_position") or "endw"

    SetVariable("doing_consider", "false")
    SetVariable("waiting_for_consider_start", "false")

    conw_on = tonumber(GetVariable("conw_on")) or 1
    conw_entry = tonumber(GetVariable("conw_entry")) or 1
    conw_kill = tonumber(GetVariable("conw_kill")) or 0
    conw_misc = tonumber(GetVariable("conw_misc")) or 1
    conw_combatend = tonumber(GetVariable("conw_combatend")) or 1
    conw_execute_mode = GetVariable("conw_execute_mode") ~= nil and GetVariable("conw_execute_mode") or "skill"
    local ignore_list = GetVariable("conw_ignore_areas")
    if ignore_list ~= nil then
        conw_ignore_areas = loadstring(string.format("return %s", ignore_list))()
    else
        conw_ignore_areas = {
            ["bootcamp"] = true
        }
    end

    ConfigureTriggers()

    if GetVariable("enabled") == "false" then
        ColourNote("yellow", "", "Warning: Plugin " .. GetPluginName() .. " is currently disabled.")
        check(EnablePlugin(GetPluginID(), false))
        return
    end -- they didn't enable us last time

    OnPluginEnable()
end -- OnPluginInstall

function OnPluginEnable()
    Load_conwall_options()
    Title_width = WindowTextWidth(Win, Font_id, TITLE .. " (" .. default_command .. ")" .. " - ON EKMC RGNW -100..+100")
    Banner_width = Title_width + BORDER_WIDTH * 2 + TEXT_OFFSET * 2
    Show_Banner()
    CheckAMB()
end -- OnPluginEnable

local amb_loaded = false
function CheckAMB()
    if amb_loaded then
        return
    end
    local amb_conw = GetInfo(60) .. "/custom/amb_conw.lua"
    if utils.readdir(amb_conw) then
        dofile(amb_conw)
        ambConwInit()
        amb_loaded = true
    end
end

function OnPluginConnect()
    Load_conwall_options()
    SetVariable("doing_consider", "false")
    SetVariable("waiting_for_consider_start", "false")
    ConfigureTriggers()
    CheckAMB()
end

function OnPluginDisable()
    WindowShow(Win, false)
end -- OnPluginDisable

function OnPluginSaveState()
    SetVariable("enabled", tostring(GetPluginInfo(GetPluginID(), 17)))
    SetVariable("doing_consider", "false")
    SetVariable("waiting_for_consider_start", "false")
    SetVariable("conw_misc", conw_misc)
    SetVariable("conw_kill", conw_kill)
    SetVariable("conw_entry", conw_entry)
    SetVariable("conw_combatend", conw_combatend)
    SetVariable("conw_on", conw_on)
    SetVariable("conw_execute_mode", conw_execute_mode)
    SetVariable("conw_ignore_areas", serialize.save_simple(conw_ignore_areas))
    movewindow.save_state(Win)
    Save_conwall_options()
end -- OnPluginSaveState
