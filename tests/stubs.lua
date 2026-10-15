-- Minimal stand-ins for the TES3MP server API and CoreScripts globals, enough
-- to load and exercise the Scavenger Scramble modules outside the server.

local stubs = {}

stubs.log = {}
stubs.chat = {}        -- array of { pid, message }
stubs.teleports = {}   -- array of { pid, cell, x, y, z, rotZ }
stubs.boxes = {}       -- array of { pid, id, kind, text }
stubs.timers = {}      -- id -> { callback, ms, args, started, stopped }
stubs.cellReset = { cleared = 0, added = {}, sent = 0 }
stubs.jsonStore = {}
stubs.playerCells = {} -- pid -> current cell description
stubs.names = {}       -- pid -> name

local nextTimerId = 1

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end
stubs.deepCopy = deepCopy

enumerations = { log = { VERBOSE = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4 },
    inventory = { SET = 0, ADD = 1, REMOVE = 2 } }

color = setmetatable({}, { __index = function(_, key) return "#" .. key end })

config = { dataPath = "./data" }

tes3mp = {}
function tes3mp.LogMessage(level, message) table.insert(stubs.log, { level = level, message = message }) end
function tes3mp.LogAppend(level, message) table.insert(stubs.log, { level = level, message = message }) end
function tes3mp.SendMessage(pid, message, toAll) table.insert(stubs.chat, { pid = pid, message = message, toAll = toAll }) end
function tes3mp.GetName(pid) return stubs.names[pid] or ("Player" .. tostring(pid)) end
function tes3mp.GetDataPath() return "./data" end
function tes3mp.GetCaseInsensitiveFilename(folder, file) return "invalid" end
function tes3mp.DoesFileExist(path)
    local name = string.gsub(path, "^%./data/", "")
    return stubs.jsonStore[name] ~= nil
end

local pending = {}
function tes3mp.SetCell(pid, cell) pending[pid] = pending[pid] or {}; pending[pid].cell = cell end
function tes3mp.SendCell(pid) end
function tes3mp.SetPos(pid, x, y, z) pending[pid] = pending[pid] or {}; pending[pid].x = x; pending[pid].y = y; pending[pid].z = z end
function tes3mp.SetRot(pid, x, z) pending[pid] = pending[pid] or {}; pending[pid].rotZ = z end
function tes3mp.SendPos(pid)
    local p = pending[pid] or {}
    table.insert(stubs.teleports, { pid = pid, cell = p.cell, x = p.x, y = p.y, z = p.z, rotZ = p.rotZ })
    stubs.playerCells[pid] = p.cell
    pending[pid] = nil
end
function tes3mp.GetCell(pid) return stubs.playerCells[pid] or "Nowhere" end
function tes3mp.GetPosX(pid) return 1 end
function tes3mp.GetPosY(pid) return 2 end
function tes3mp.GetPosZ(pid) return 3 end
function tes3mp.GetRotX(pid) return 0 end
function tes3mp.GetRotZ(pid) return 0 end

function tes3mp.CreateTimer(callback, ms)
    local id = nextTimerId
    nextTimerId = nextTimerId + 1
    stubs.timers[id] = { callback = callback, ms = ms, args = {}, started = false, stopped = false }
    return id
end
function tes3mp.CreateTimerEx(callback, ms, types, ...)
    local id = tes3mp.CreateTimer(callback, ms)
    stubs.timers[id].args = { ... }
    return id
end
function tes3mp.StartTimer(id) stubs.timers[id].started = true end
function tes3mp.StopTimer(id) if stubs.timers[id] then stubs.timers[id].stopped = true end end
function tes3mp.RestartTimer(id, ms)
    local timer = assert(stubs.timers[id], "RestartTimer on unknown timer " .. tostring(id))
    timer.ms = ms
    timer.started = true
    timer.stopped = false
end
function tes3mp.IsTimerElapsed(id) return false end
-- FreeTimer breaks every later CreateTimer on the real server (see util.lua), so the
-- stub counts calls and fails loudly.
stubs.freeTimerCalls = 0
function tes3mp.FreeTimer(id)
    stubs.freeTimerCalls = stubs.freeTimerCalls + 1
    error("tes3mp.FreeTimer must never be called: TES3MP 0.8.1 breaks every timer created after a free")
end

function tes3mp.CustomMessageBox(pid, id, text, buttons) table.insert(stubs.boxes, { pid = pid, id = id, kind = "custom", text = text }) end
function tes3mp.MessageBox(pid, id, text) table.insert(stubs.boxes, { pid = pid, id = id, kind = "message", text = text }) end
function tes3mp.ListBox(pid, id, label, items) table.insert(stubs.boxes, { pid = pid, id = id, kind = "list", text = items }) end
function tes3mp.InputDialog(pid, id, label, note) table.insert(stubs.boxes, { pid = pid, id = id, kind = "input", text = label }) end

function tes3mp.ClearCellsToReset() stubs.cellReset.cleared = stubs.cellReset.cleared + 1; stubs.cellReset.added = {} end
function tes3mp.AddCellToReset(desc) table.insert(stubs.cellReset.added, desc) end
function tes3mp.SendCellReset(pid, toAll) stubs.cellReset.sent = stubs.cellReset.sent + 1 end

-- Fire a timer by its callback name (all matching started timers), passing stored args.
function stubs.fireTimers(callbackName)
    local fired = 0
    for id, timer in pairs(stubs.timers) do
        if timer.callback == callbackName and timer.started and not timer.stopped then
            timer.stopped = true
            _G[callbackName](unpack(timer.args))
            fired = fired + 1
        end
    end
    return fired
end

-- Every timer ever created for a callback, whatever its state.
function stubs.timersCreated(callbackName)
    local n = 0
    for _, timer in pairs(stubs.timers) do
        if timer.callback == callbackName then n = n + 1 end
    end
    return n
end

function stubs.timersNamed(callbackName)
    local list = {}
    for id, timer in pairs(stubs.timers) do
        if timer.callback == callbackName and timer.started and not timer.stopped then
            table.insert(list, timer)
        end
    end
    return list
end

-- customEventHooks / customCommandHooks --------------------------------------

customEventHooks = { handlers = {}, validators = {} }
function customEventHooks.registerHandler(event, callback)
    customEventHooks.handlers[event] = customEventHooks.handlers[event] or {}
    table.insert(customEventHooks.handlers[event], callback)
end
function customEventHooks.registerValidator(event, callback)
    customEventHooks.validators[event] = customEventHooks.validators[event] or {}
    table.insert(customEventHooks.validators[event], callback)
end
function customEventHooks.makeEventStatus(a, b) return { validDefaultHandler = a, validCustomHandlers = b } end
function customEventHooks.fire(event, ...)
    local status = customEventHooks.makeEventStatus(true, true)
    for _, callback in ipairs(customEventHooks.handlers[event] or {}) do
        callback(status, ...)
    end
end

customCommandHooks = { commands = {} }
function customCommandHooks.registerCommand(name, callback) customCommandHooks.commands[name] = callback end
function customCommandHooks.run(pid, line)
    local cmd = {}
    for word in string.gmatch(line, "%S+") do table.insert(cmd, word) end
    local callback = customCommandHooks.commands[cmd[1]]
    assert(callback ~= nil, "no command " .. tostring(cmd[1]))
    callback(pid, cmd)
end

-- jsonInterface (in memory) --------------------------------------------------

jsonInterface = {}
function jsonInterface.save(fileName, data) stubs.jsonStore[fileName] = deepCopy(data); return true end
function jsonInterface.quicksave(fileName, data) return jsonInterface.save(fileName, data) end
function jsonInterface.load(fileName)
    local data = stubs.jsonStore[fileName]
    if data == nil then return nil end
    return deepCopy(data)
end

-- Players, cells -------------------------------------------------------------

Players = {}
LoadedCells = {}

function stubs.addPlayer(pid, name, staffRank, inventory)
    stubs.names[pid] = name
    local player = {
        pid = pid,
        accountName = name,
        loggedIn = true,
        data = {
            settings = { staffRank = staffRank or 0 },
            inventory = inventory or {},
            location = { cell = "Nowhere" },
        },
    }
    function player:IsLoggedIn() return self.loggedIn end
    function player:IsAdmin() return self.data.settings.staffRank >= 2 end
    function player:IsModerator() return self.data.settings.staffRank >= 1 end
    Players[pid] = player
    return player
end

function stubs.removePlayer(pid)
    Players[pid] = nil
    stubs.names[pid] = nil
end

function stubs.giveItem(pid, refId, count)
    local inventory = Players[pid].data.inventory
    for _, item in ipairs(inventory) do
        if item.refId == refId then item.count = item.count + (count or 1); return end
    end
    table.insert(inventory, { refId = refId, count = count or 1, charge = -1, enchantmentCharge = -1, soul = "" })
end

local FakeCell = {}
FakeCell.__index = FakeCell
function FakeCell:HasEntry() return self.hasEntry end
function FakeCell:EnsurePacketTables() self.data.packets = self.data.packets or {} end
function FakeCell:ClearRecordLinks() self.data.recordLinks = {} end
function FakeCell:QuicksaveToDrive() end
function FakeCell:SaveToDrive() end

stubs.cellEntries = {}   -- description -> true when the cell "has a file"

function Cell(description)
    local cell = setmetatable({
        description = description,
        hasEntry = stubs.cellEntries[description] == true,
        isResetting = false,
        data = { objectData = { something = 1 }, packets = { place = {} }, loadState = { hasFullActorList = true, hasFullContainerData = true }, recordLinks = {} },
    }, FakeCell)
    return cell
end

logicHandler = {}
function logicHandler.LoadCell(description) LoadedCells[description] = Cell(description) end
function logicHandler.UnloadCell(description) LoadedCells[description] = nil end

function stubs.reset()
    stubs.log = {}
    stubs.chat = {}
    stubs.teleports = {}
    stubs.boxes = {}
    stubs.cellReset = { cleared = 0, added = {}, sent = 0 }
    stubs.playerCells = {}
end

function stubs.clearTimers()
    stubs.timers = {}
end

function stubs.chatContaining(text)
    local hits = {}
    for _, entry in ipairs(stubs.chat) do
        if string.find(entry.message, text, 1, true) then table.insert(hits, entry) end
    end
    return hits
end

function stubs.lastTeleport(pid)
    for i = #stubs.teleports, 1, -1 do
        if stubs.teleports[i].pid == pid then return stubs.teleports[i] end
    end
    return nil
end

return stubs
