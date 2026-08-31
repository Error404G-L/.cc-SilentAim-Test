local nativeTypeof = typeof
local function typeof(value)
    if type(value) == "table" and rawget(value, "__type") then
        return rawget(value, "__type")
    end
    return nativeTypeof(value)
end

local function vector(kind, x, y, z)
    local result = { __type = kind, X = x or 0, Y = y or 0, Z = z or 0 }
    return setmetatable(result, {
        __index = function(self, key)
            if key == "Magnitude" then
                return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
            elseif key == "Unit" then
                local length = self.Magnitude
                return vector(kind, self.X / length, self.Y / length, self.Z / length)
            end
        end,
        __add = function(a, b) return vector(kind, a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
        __sub = function(a, b) return vector(kind, a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
        __mul = function(a, b) return vector(kind, a.X * b, a.Y * b, a.Z * b) end,
        __div = function(a, b) return vector(kind, a.X / b, a.Y / b, a.Z / b) end
    })
end

local Vector2 = { new = function(x, y) return vector("Vector2", x, y, 0) end }
local Vector3 = { new = function(x, y, z) return vector("Vector3", x, y, z) end }
local CFrame = { new = function(x, y, z)
    return { __type = "CFrame", Position = Vector3.new(x, y, z) }
end }
local Ray = { new = function(origin, direction)
    return { __type = "Ray", Origin = origin, Direction = direction }
end }
local RaycastParams = { new = function() return { __type = "RaycastParams" } end }
local Color3 = { fromRGB = function(r, g, b) return { r, g, b } end }
local UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }
local UDim2 = {
    new = function(xs, xo, ys, yo) return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) } end,
    fromOffset = function(x, y) return { X = UDim.new(0, x), Y = UDim.new(0, y) } end
}
local Enum = setmetatable({}, {
    __index = function(self, group)
        local entries = setmetatable({}, {
            __index = function(items, name)
                local value = { Name = name, __type = "EnumItem" }
                rawset(items, name, value)
                return value
            end
        })
        rawset(self, group, entries)
        return entries
    end
})

local function signal()
    local callbacks = {}
    return {
        Connect = function(self, callback)
            local entry = { Connected = true, Callback = callback }
            function entry:Disconnect() self.Connected = false end
            table.insert(callbacks, entry)
            return entry
        end,
        Fire = function(self, ...)
            for _, entry in ipairs(table.clone(callbacks)) do
                if entry.Connected then entry.Callback(...) end
            end
        end,
        Count = function()
            local count = 0
            for _, entry in ipairs(callbacks) do
                if entry.Connected then count = count + 1 end
            end
            return count
        end
    }
end

local methods = {}
local function object(className, parent)
    local result = { __type = "Instance", _children = {}, _props = {
        ClassName = className, Name = className, Visible = true,
        AbsolutePosition = Vector2.new(12, 64), AbsoluteSize = Vector2.new(300, 330)
    } }
    if className == "TextButton" then result._props.Activated = signal() end
    setmetatable(result, {
        __index = function(self, key) return methods[key] or self._props[key] end,
        __newindex = function(self, key, value)
            if key == "Parent" then
                local old = self._props.Parent
                if old then
                    local index = table.find(old._children, self)
                    if index then table.remove(old._children, index) end
                end
                if value then table.insert(value._children, self) end
            end
            self._props[key] = value
        end
    })
    result.Parent = parent
    return result
end
function methods:IsA(className)
    return self.ClassName == className or (className == "BasePart" and self.ClassName == "Part")
end
function methods:FindFirstChild(name)
    for _, child in ipairs(self._children) do
        if child.Name == name then return child end
    end
end
function methods:FindFirstChildOfClass(className)
    for _, child in ipairs(self._children) do
        if child:IsA(className) then return child end
    end
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:IsDescendantOf(ancestor)
    local current = self.Parent
    while current do
        if current == ancestor then return true end
        current = current.Parent
    end
    return false
end
function methods:Destroy()
    for _, child in ipairs(table.clone(self._children)) do child:Destroy() end
    self.Parent = nil
end
local Instance = { new = object }
local game = object("DataModel")
game.IsLoaded = function() return true end
local workspace = object("Workspace", game)
local Players = object("Players", game)
local Input = {
    MouseEnabled = true,
    MouseBehavior = Enum.MouseBehavior.Default,
    InputBegan = signal(),
    Pointer = Vector2.new(512, 384),
    LastInput = Enum.UserInputType.MouseMovement,
    GetMouseLocation = function(self) return self.Pointer end,
    GetLastInputType = function(self) return self.LastInput end,
    GetFocusedTextBox = function(self) return self.Focused end
}
local RunService = { RenderStepped = signal() }
local services = { Players = Players, UserInputService = Input, RunService = RunService }
game.GetService = function(self, name) return assert(services[name], name) end
Players.GetPlayers = function(self)
    local result = {}
    for _, child in ipairs(self._children) do
        if child:IsA("Player") then table.insert(result, child) end
    end
    return result
end
local mouse = object("Mouse")
local localPlayer = object("Player", Players)
localPlayer.Name = "Local"
localPlayer.Neutral = true
localPlayer.GetMouse = function() return mouse end
Players.LocalPlayer = localPlayer
local playerGui = object("PlayerGui", localPlayer)
local visibilityBlocker = nil
local raycastCount = 0
workspace.Raycast = function(self, origin, direction, params)
    raycastCount = raycastCount + 1
    if visibilityBlocker then return { Instance = visibilityBlocker } end
    return nil
end

local function makeCharacter(owner, x, y, z)
    local character = object("Model", workspace)
    local head = object("Part", character)
    head.Name = "Head"
    head.Position = Vector3.new(x, y, z)
    head.CFrame = CFrame.new(x, y, z)
    local humanoid = object("Humanoid", character)
    humanoid.Health = 100
    owner.Character = character
    return head, humanoid
end

local function enemy(name, x, y, z)
    local candidate = object("Player", Players)
    candidate.Name = name
    candidate.Neutral = true
    local head, humanoid = makeCharacter(candidate, x, y, z)
    return candidate, head, humanoid
end

local environment = {}
local hooks = {}
local hookCount = 0
local callerIsExecutor = false
local currentMethod = "Raycast"
local originalArguments = nil
local originalMethod = nil
local originalResult = {}
local function getgenv() return environment end
local function checkcaller() return callerIsExecutor end
local function getnamecallmethod() return currentMethod end
local function newcclosure(callback) return callback end
local function hookmetamethod(target, name, callback)
    hookCount = hookCount + 1
    local previous = hooks[name]
    if not previous then
        previous = function(...)
            originalArguments = table.pack(...)
            originalMethod = name
            return originalResult, nil, "third"
        end
    end
    hooks[name] = callback
    return previous
end

local function read(key, targetObject)
    return hooks.__index(targetObject or mouse, key)
end
local function call(method, ...)
    currentMethod = method
    return hooks.__namecall(workspace, ...)
end
