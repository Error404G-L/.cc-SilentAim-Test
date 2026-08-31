local Settings = {
    Enabled = true,
    Method = "Raycast",
    Radius = 150,
    MaxDistance = 1500,
    TeamCheck = true,
    VisibilityCheck = true,
    RequireTool = true,
    ShowUI = true,
    ShowFOV = true,
    AimOrigin = "Auto",
    ToggleKey = Enum.KeyCode.RightAlt,
    MethodKey = Enum.KeyCode.F6,
    UnloadKey = Enum.KeyCode.End
}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function finiteVector(value)
    return typeof(value) == "Vector3"
        and finite(value.X) and finite(value.Y) and finite(value.Z)
end

assert(type(hookmetamethod) == "function", "hookmetamethod is unavailable.")
assert(type(checkcaller) == "function", "checkcaller is unavailable.")
assert(type(newcclosure) == "function", "newcclosure is unavailable.")

local hookFunction = hookmetamethod
local executorCaller = checkcaller
local nativeClosure = newcclosure
local namecallMethod = getnamecallmethod

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local environment = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        environment = result
    end
end

local registryKey = "__IDERR_SilentAim_Bridge_v1"
local bridge = environment[registryKey]
if bridge ~= nil then
    assert(type(bridge) == "table" and bridge.Version == 1, "Runtime registry conflict.")
    assert(not bridge.Failed, "A previous hook installation failed. Start a fresh session.")
else
    bridge = { Version = 1 }
    local stored, storeError = pcall(function() environment[registryKey] = bridge end)
    assert(stored, "A writable shared environment is required: " .. tostring(storeError))
end

local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "A running Roblox client is required.")

local mouse = player:GetMouse()
local rawRaycast = workspace.Raycast
local connections = {}
local runtime = {
    Settings = Settings,
    Stopped = false,
    Target = nil,
    UpdatedAt = 0,
    Status = "Starting",
    Gui = nil
}

local methodList = { "Mouse.Hit/Target" }
if type(namecallMethod) == "function" then
    methodList = {
        "Raycast",
        "Mouse.Hit/Target",
        "FindPartOnRay",
        "FindPartOnRayWithIgnoreList",
        "FindPartOnRayWithWhitelist"
    }
end
if not table.find(methodList, Settings.Method) then
    Settings.Method = methodList[1]
end

local legacyMethods = {
    FindPartOnRay = true,
    FindPartOnRayWithIgnoreList = true,
    FindPartOnRayWithWhitelist = true
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

function runtime:Stop()
    if self.Stopped then
        return
    end
    self.Stopped = true
    self.Target = nil
    if bridge.Active == self then
        bridge.Active = nil
    end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    if self.Gui then
        self.Gui:Destroy()
        self.Gui = nil
    end
end

function runtime:Fault(message)
    Settings.Enabled = false
    self.Target = nil
    self.Status = "Paused: " .. tostring(message)
    warn("Silent Aim: " .. tostring(message))
end

function runtime:SetEnabled(value)
    Settings.Enabled = value == true
    self.Target = nil
    self.Status = Settings.Enabled and "Searching" or "Disabled"
end

function runtime:NextMethod()
    local index = table.find(methodList, Settings.Method) or 0
    Settings.Method = methodList[index % #methodList + 1]
    self.Target = nil
end

local function aimPosition(camera)
    local lastInput = Input:GetLastInputType()
    local centered = Settings.AimOrigin == "Center"
        or (Settings.AimOrigin == "Auto" and (
            not Input.MouseEnabled
            or Input.MouseBehavior == Enum.MouseBehavior.LockCenter
            or lastInput == Enum.UserInputType.Touch
            or string.find(lastInput.Name, "Gamepad", 1, true) ~= nil
        ))
    if centered then
        return camera.ViewportSize / 2
    end
    return Input:GetMouseLocation()
end

local function validCandidate(candidate)
    if candidate == player or candidate.Parent ~= Players then
        return nil
    end
    if Settings.TeamCheck and not player.Neutral and not candidate.Neutral
        and candidate.Team == player.Team
    then
        return nil
    end
    local character = candidate.Character
    local head = character and character:FindFirstChild("Head")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not character:IsDescendantOf(workspace)
        or not head or not head:IsA("BasePart")
        or not humanoid or humanoid.Health <= 0
    then
        return nil
    end
    return head, character, humanoid
end

local function localReady()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
        and (not Settings.RequireTool or character:FindFirstChildOfClass("Tool") ~= nil)
end

local function visibleFrom(origin, head, character, params)
    local offset = head.Position - origin
    if offset.Magnitude < 0.0001 then
        return true
    end
    local result = rawRaycast(workspace, origin, offset, params)
    return result == nil or result.Instance:IsDescendantOf(character)
end

local panel, circle, statusLabel, enabledButton, methodButton, teamButton, wallButton, toolButton

local function updateTarget()
    runtime.Target = nil
    runtime.UpdatedAt = os.clock()
    local camera = workspace.CurrentCamera
    if not Settings.Enabled or not camera then
        return
    end
    if Input:GetFocusedTextBox() then
        runtime.Status = "Paused while typing"
        return
    end
    if not localReady() then
        runtime.Status = Settings.RequireTool and "Equip a Tool to activate" or "Waiting for character"
        return
    end
    local cursor = aimPosition(camera)
    if panel and panel.Visible and Input.MouseEnabled then
        local pointer = Input:GetMouseLocation()
        local start, size = panel.AbsolutePosition, panel.AbsoluteSize
        if pointer.X >= start.X and pointer.X <= start.X + size.X
            and pointer.Y >= start.Y and pointer.Y <= start.Y + size.Y
        then
            runtime.Status = "Paused over controls"
            return
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character, camera }
    params.IgnoreWater = true
    local closestDistance = Settings.Radius
    local origin = camera.CFrame.Position
    for _, candidate in ipairs(Players:GetPlayers()) do
        local head, character, humanoid = validCandidate(candidate)
        if head and finiteVector(head.Position)
            and (head.Position - origin).Magnitude <= Settings.MaxDistance
        then
            local point, onScreen = camera:WorldToViewportPoint(head.Position)
            if onScreen and point.Z > 0 then
                local distance = (Vector2.new(point.X, point.Y) - cursor).Magnitude
                if distance <= closestDistance
                    and (not Settings.VisibilityCheck or visibleFrom(origin, head, character, params))
                then
                    closestDistance = distance
                    runtime.Target = {
                        Player = candidate,
                        Character = character,
                        Head = head,
                        Humanoid = humanoid
                    }
                end
            end
        end
    end
    runtime.Status = runtime.Target and ("Target: " .. runtime.Target.Player.Name) or "No target in radius"
end

local function currentHead()
    local selected = runtime.Target
    if runtime.Stopped or not Settings.Enabled or not selected
        or os.clock() - runtime.UpdatedAt > 0.2 or not localReady()
    then
        return nil
    end
    local head, character = validCandidate(selected.Player)
    if head ~= selected.Head or character ~= selected.Character then
        return nil
    end
    return head
end

function runtime:Read(object, key)
    if Settings.Method ~= "Mouse.Hit/Target" or object ~= mouse then
        return false
    end
    if key ~= "Hit" and key ~= "hit" and key ~= "Target" and key ~= "target" then
        return false
    end
    local head = currentHead()
    if not head then
        return false
    end
    if key == "Hit" or key == "hit" then
        return true, head.CFrame
    end
    return true, head
end

function runtime:Redirect(object, method, arguments)
    if object ~= workspace then
        return false
    end
    if method == "findPartOnRay" then
        method = "FindPartOnRay"
    end
    if method ~= Settings.Method or (method ~= "Raycast" and not legacyMethods[method]) then
        return false
    end
    local origin, direction
    if method == "Raycast" then
        origin, direction = arguments[1], arguments[2]
        if arguments.n < 2 or arguments.n > 3
            or (arguments[3] ~= nil and typeof(arguments[3]) ~= "RaycastParams")
        then
            return false
        end
    else
        local ray = arguments[1]
        if typeof(ray) ~= "Ray" then
            return false
        end
        if method == "FindPartOnRay" then
            if arguments[2] ~= nil and typeof(arguments[2]) ~= "Instance" then
                return false
            end
        elseif type(arguments[2]) ~= "table" then
            return false
        end
        local maximum = method == "FindPartOnRayWithWhitelist" and 3 or 4
        if arguments.n > maximum then
            return false
        end
        for index = 3, arguments.n do
            if arguments[index] ~= nil and type(arguments[index]) ~= "boolean" then
                return false
            end
        end
        origin, direction = ray.Origin, ray.Direction
    end
    if not finiteVector(origin) or not finiteVector(direction) then
        return false
    end
    local length = direction.Magnitude
    local head = currentHead()
    if not head or length <= 0.0001 or not finite(length) or not finiteVector(head.Position) then
        return false
    end
    local offset = head.Position - origin
    if offset.Magnitude <= 0.0001 then
        return false
    end
    local replacement = offset.Unit * length
    if not finiteVector(replacement) then
        return false
    end
    if method == "Raycast" then
        arguments[2] = replacement
    else
        arguments[1] = Ray.new(origin, replacement)
    end
    return true
end

local function create(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function buildUI()
    if not Settings.ShowUI then
        return
    end
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
        or player:WaitForChild("PlayerGui", 10)
    assert(playerGui, "PlayerGui is unavailable.")
    runtime.Gui = create("ScreenGui", {
        Name = "SilentAimControls",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 100
    }, playerGui)
    circle = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 1
    }, runtime.Gui)
    create("UICorner", { CornerRadius = UDim.new(1, 0) }, circle)
    create("UIStroke", { Color = Color3.fromRGB(99, 190, 255), Thickness = 1 }, circle)
    panel = create("Frame", {
        Position = UDim2.fromOffset(12, 64),
        Size = UDim2.fromOffset(300, 330),
        BackgroundColor3 = Color3.fromRGB(23, 26, 33),
        BorderSizePixel = 0,
        ZIndex = 2
    }, runtime.Gui)
    create("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
    create("TextLabel", {
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 28),
        BackgroundTransparency = 1,
        Text = "Silent Aim",
        TextColor3 = Color3.fromRGB(240, 243, 250),
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3
    }, panel)
    local function button(y, action)
        local item = create("TextButton", {
            Position = UDim2.fromOffset(12, y),
            Size = UDim2.new(1, -24, 0, 30),
            BackgroundColor3 = Color3.fromRGB(39, 46, 59),
            TextColor3 = Color3.fromRGB(240, 243, 250),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            Text = "",
            BorderSizePixel = 0,
            Selectable = true,
            Modal = false,
            ZIndex = 3
        }, panel)
        create("UICorner", { CornerRadius = UDim.new(0, 6) }, item)
        connect(item.Activated, action)
        return item
    end
    enabledButton = button(42, function() runtime:SetEnabled(not Settings.Enabled) end)
    methodButton = button(78, function() runtime:NextMethod() end)
    teamButton = button(114, function() Settings.TeamCheck = not Settings.TeamCheck; runtime.Target = nil end)
    wallButton = button(150, function() Settings.VisibilityCheck = not Settings.VisibilityCheck; runtime.Target = nil end)
    toolButton = button(186, function() Settings.RequireTool = not Settings.RequireTool; runtime.Target = nil end)
    local close = button(222, function() runtime:Stop() end)
    close.Text = "Unload"
    statusLabel = create("TextLabel", {
        Position = UDim2.fromOffset(12, 258),
        Size = UDim2.new(1, -24, 0, 60),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(173, 187, 204),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextWrapped = true,
        Text = "Starting",
        ZIndex = 3
    }, panel)
end

local function updateUI()
    if not runtime.Gui or not runtime.Gui.Parent then
        return
    end
    local camera = workspace.CurrentCamera
    circle.Visible = Settings.ShowFOV and Settings.Enabled and camera ~= nil
    if camera then
        local cursor = aimPosition(camera)
        circle.Position = UDim2.fromOffset(cursor.X, cursor.Y)
        circle.Size = UDim2.fromOffset(Settings.Radius * 2, Settings.Radius * 2)
        local scale = math.min(1, camera.ViewportSize.X / 324, camera.ViewportSize.Y / 420)
        local scaler = panel:FindFirstChildOfClass("UIScale")
            or create("UIScale", {}, panel)
        scaler.Scale = math.max(0.3, scale)
    end
    enabledButton.Text = Settings.Enabled and "Enabled" or "Disabled"
    methodButton.Text = "Method: " .. Settings.Method
    teamButton.Text = "Team check: " .. (Settings.TeamCheck and "On" or "Off")
    wallButton.Text = "Visibility check: " .. (Settings.VisibilityCheck and "On" or "Off")
    toolButton.Text = "Require equipped Tool: " .. (Settings.RequireTool and "On" or "Off")
    statusLabel.Text = runtime.Status .. "\nRight Alt: toggle | F6: method | End: unload"
end

local function installHooks()
    if not bridge.IndexInstalled then
        local previous
        previous = hookFunction(game, "__index", nativeClosure(function(object, key)
            local active = bridge.Active
            if active and active.Settings.Enabled and not executorCaller() then
                local ok, handled, value = pcall(active.Read, active, object, key)
                if not ok then
                    active:Fault(handled)
                elseif handled then
                    return value
                end
            end
            return previous(object, key)
        end))
        assert(type(previous) == "function", "Invalid original __index handler.")
        bridge.IndexInstalled = true
    end
    if type(namecallMethod) == "function" and not bridge.NamecallInstalled then
        local previous
        previous = hookFunction(game, "__namecall", nativeClosure(function(object, ...)
            local method = namecallMethod()
            local active = bridge.Active
            if active and active.Settings.Enabled and object == workspace and not executorCaller() then
                local normalized = method == "findPartOnRay" and "FindPartOnRay" or method
                if normalized == active.Settings.Method then
                    local arguments = table.pack(...)
                    local ok, handled = pcall(active.Redirect, active, object, method, arguments)
                    if not ok then
                        active:Fault(handled)
                    elseif handled then
                        return previous(object, table.unpack(arguments, 1, arguments.n))
                    end
                end
            end
            return previous(object, ...)
        end))
        assert(type(previous) == "function", "Invalid original __namecall handler.")
        bridge.NamecallInstalled = true
    end
end

if bridge.Active then
    bridge.Active:Stop()
end

local hookOK, hookError = pcall(installHooks)
if not hookOK then
    bridge.Failed = true
    runtime:Stop()
    error("Hook installation failed: " .. tostring(hookError), 0)
end

local uiOK, uiError = pcall(buildUI)
if not uiOK then
    runtime:Stop()
    error("Control setup failed: " .. tostring(uiError), 0)
end

bridge.Active = runtime
connect(Input.InputBegan, function(input, processed)
    if processed or Input:GetFocusedTextBox() then
        return
    end
    if input.KeyCode == Settings.ToggleKey then
        runtime:SetEnabled(not Settings.Enabled)
    elseif input.KeyCode == Settings.MethodKey then
        runtime:NextMethod()
    elseif input.KeyCode == Settings.UnloadKey then
        runtime:Stop()
    end
end)
connect(RunService.RenderStepped, function()
    if runtime.Stopped then
        return
    end
    if Settings.ShowUI and (not runtime.Gui or not runtime.Gui.Parent) then
        runtime:Stop()
        return
    end
    local ok, message = pcall(function()
        assert(finite(Settings.Radius) and Settings.Radius >= 0, "Radius must be nonnegative and finite.")
        assert(finite(Settings.MaxDistance) and Settings.MaxDistance > 0, "MaxDistance must be positive and finite.")
        updateTarget()
        updateUI()
    end)
    if not ok then
        runtime:Fault(message)
        runtime:Stop()
    end
end)

return runtime
