local total = 0
local active

local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001, tostring(actual) .. " differs from " .. tostring(expected))
end
local function frame()
    RunService.RenderStepped:Fire(1 / 60)
end
local function fresh()
    if active then active:Stop() end
    for _, candidate in ipairs(Players:GetPlayers()) do
        if candidate ~= localPlayer then
            if candidate.Character then candidate.Character:Destroy() end
            candidate:Destroy()
        end
    end
    if localPlayer.Character then localPlayer.Character:Destroy() end
    makeCharacter(localPlayer, 512, 384, 10)
    object("Tool", localPlayer.Character)
    localPlayer.Neutral = true
    localPlayer.Team = nil
    local camera = object("Camera", workspace)
    camera.CFrame = CFrame.new(0, 0, 0)
    camera.ViewportSize = Vector2.new(1024, 768)
    camera.WorldToViewportPoint = function(self, position)
        return position, position.X >= 0 and position.X <= self.ViewportSize.X
            and position.Y >= 0 and position.Y <= self.ViewportSize.Y
    end
    workspace.CurrentCamera = camera
    Input.MouseEnabled = true
    Input.MouseBehavior = Enum.MouseBehavior.Default
    Input.LastInput = Enum.UserInputType.MouseMovement
    Input.Pointer = Vector2.new(512, 384)
    Input.Focused = nil
    visibilityBlocker = nil
    callerIsExecutor = false
    originalArguments = nil
    active = launch()
    equal(active.Stopped, false)
    return active
end
local function test(name, callback)
    fresh()
    callback()
    total = total + 1
    print("PASS " .. name)
end

test("nearest living head in 150-pixel radius", function()
    enemy("Farther", 600, 384, 100)
    local candidate, head = enemy("Nearest", 525, 390, 100)
    frame()
    equal(active.Target.Head, head)
    equal(active.Target.Player, candidate)
end)

test("radius boundary included, outside excluded", function()
    local candidate = enemy("Boundary", 662, 384, 100)
    frame()
    equal(active.Target.Player, candidate)
    active.Settings.Radius = 149.9
    frame()
    equal(active.Target, nil)
end)

test("dead, behind-camera and offscreen players excluded", function()
    local dead, head, humanoid = enemy("Dead", 512, 384, 100)
    humanoid.Health = 0
    enemy("Behind", 512, 384, -10)
    enemy("Offscreen", 1100, 384, 100)
    frame()
    equal(active.Target, nil)
end)

test("local character is never a target", function()
    frame()
    equal(active.Target, nil)
end)

test("team check respects neutral players", function()
    local candidate = enemy("SameTeam", 525, 390, 100)
    localPlayer.Team = "Blue"
    candidate.Team = "Blue"
    localPlayer.Neutral = false
    candidate.Neutral = false
    frame()
    equal(active.Target, nil)
    candidate.Neutral = true
    frame()
    equal(active.Target.Player, candidate)
end)

test("visibility blockers excluded", function()
    enemy("Blocked", 525, 390, 100)
    visibilityBlocker = object("Part", workspace)
    frame()
    equal(active.Target, nil)
    active.Settings.VisibilityCheck = false
    frame()
    assert(active.Target)
end)

test("hitting target character counts as visible", function()
    local candidate, head = enemy("Visible", 525, 390, 100)
    visibilityBlocker = head
    frame()
    equal(active.Target.Player, candidate)
end)

test("camera replacement and temporarily missing camera", function()
    enemy("Target", 525, 390, 100)
    local camera = workspace.CurrentCamera
    workspace.CurrentCamera = nil
    frame()
    equal(active.Target, nil)
    workspace.CurrentCamera = camera
    frame()
    assert(active.Target)
end)

test("equipped Tool gate can be disabled for custom weapons", function()
    enemy("Target", 525, 390, 100)
    localPlayer.Character:FindFirstChildOfClass("Tool"):Destroy()
    frame()
    equal(active.Target, nil)
    active.Settings.RequireTool = false
    frame()
    assert(active.Target)
end)

test("typing pauses selection", function()
    enemy("Target", 525, 390, 100)
    Input.Focused = {}
    frame()
    equal(active.Target, nil)
end)

test("mouse over control panel pauses selection", function()
    Input.Pointer = Vector2.new(100, 100)
    enemy("Target", 110, 110, 100)
    frame()
    equal(active.Target, nil)
end)

test("touch uses viewport center", function()
    Input.Pointer = Vector2.new(0, 0)
    Input.LastInput = Enum.UserInputType.Touch
    local candidate = enemy("Center", 525, 390, 100)
    frame()
    equal(active.Target.Player, candidate)
end)

test("gamepad uses viewport center", function()
    Input.Pointer = Vector2.new(0, 0)
    Input.LastInput = Enum.UserInputType.Gamepad1
    enemy("Center", 525, 390, 100)
    frame()
    assert(active.Target)
end)

test("distance cap applied", function()
    enemy("Distant", 525, 390, 2000)
    frame()
    equal(active.Target, nil)
end)

test("Hit and Target return different correct types", function()
    active.Settings.Method = "Mouse.Hit/Target"
    local candidate, head = enemy("Target", 525, 390, 100)
    frame()
    equal(read("Hit"), head.CFrame)
    equal(read("Target"), head)
    equal(read("hit"), head.CFrame)
    equal(read("target"), head)
end)

test("unrelated mouse reads pass through without recursion", function()
    active.Settings.Method = "Mouse.Hit/Target"
    enemy("Target", 525, 390, 100)
    frame()
    for _, key in ipairs({ "X", "Y", "UnitRay", "Origin" }) do
        equal(read(key), originalResult)
        equal(originalArguments[2], key)
    end
end)

test("executor callers are not redirected", function()
    active.Settings.Method = "Mouse.Hit/Target"
    enemy("Target", 525, 390, 100)
    frame()
    callerIsExecutor = true
    equal(read("Hit"), originalResult)
end)

test("Raycast preserves range, origin, params, and return values", function()
    enemy("Target", 525, 390, 100)
    frame()
    local origin = Vector3.new(0, 0, 0)
    local params = RaycastParams.new()
    local a, b, c = call("Raycast", origin, Vector3.new(0, 0, 73), params)
    equal(a, originalResult)
    equal(b, nil)
    equal(c, "third")
    equal(originalArguments[2], origin)
    near(originalArguments[3].Magnitude, 73)
    assert(originalArguments[3].X > 0)
    equal(originalArguments[4], params)
    equal(originalArguments.n, 4)
end)

test("optional trailing nil retained", function()
    enemy("Target", 525, 390, 100)
    frame()
    call("Raycast", Vector3.new(), Vector3.new(0, 0, 100), nil)
    equal(originalArguments.n, 4)
    equal(originalArguments[4], nil)
end)

test("zero-length and nonfinite rays pass through", function()
    enemy("Target", 525, 390, 100)
    frame()
    for _, direction in ipairs({ Vector3.new(), Vector3.new(math.huge, 0, 0), Vector3.new(0 / 0, 0, 0) }) do
        call("Raycast", Vector3.new(), direction)
        equal(originalArguments[3], direction)
    end
end)

test("coincident origin does not normalize zero", function()
    local candidate, head = enemy("Target", 525, 390, 100)
    frame()
    local direction = Vector3.new(0, 0, 100)
    call("Raycast", head.Position, direction)
    equal(originalArguments[3], direction)
end)

test("invalid Raycast argument types pass through", function()
    enemy("Target", 525, 390, 100)
    frame()
    local direction = Vector3.new(0, 0, 100)
    local invalidParams = {}
    call("Raycast", Vector3.new(), direction, invalidParams)
    equal(originalArguments[3], direction)
    call("Raycast", "bad origin", direction)
    equal(originalArguments[2], "bad origin")
end)

test("nonselected methods pass through", function()
    enemy("Target", 525, 390, 100)
    frame()
    local ray = Ray.new(Vector3.new(), Vector3.new(0, 0, 100))
    call("FindPartOnRay", ray)
    equal(originalArguments[2], ray)
end)

test("all legacy methods preserve ray length and filters", function()
    enemy("Target", 525, 390, 100)
    frame()
    for _, method in ipairs({ "FindPartOnRay", "FindPartOnRayWithIgnoreList", "FindPartOnRayWithWhitelist" }) do
        active.Settings.Method = method
        local ray = Ray.new(Vector3.new(), Vector3.new(0, 0, 19))
        local filter = method == "FindPartOnRay" and localPlayer.Character or { localPlayer.Character }
        call(method, ray, filter, false)
        near(originalArguments[2].Direction.Magnitude, 19)
        equal(originalArguments[2].Origin, ray.Origin)
        equal(originalArguments[3], filter)
        equal(originalArguments[4], false)
    end
end)

test("legacy lowercase method alias supported", function()
    active.Settings.Method = "FindPartOnRay"
    enemy("Target", 525, 390, 100)
    frame()
    local ray = Ray.new(Vector3.new(), Vector3.new(0, 0, 100))
    call("findPartOnRay", ray)
    assert(originalArguments[2] ~= ray)
end)

test("invalid legacy optional flags pass through", function()
    active.Settings.Method = "FindPartOnRayWithIgnoreList"
    enemy("Target", 525, 390, 100)
    frame()
    local ray = Ray.new(Vector3.new(), Vector3.new(0, 0, 100))
    call("FindPartOnRayWithIgnoreList", ray, {}, "not boolean")
    equal(originalArguments[2], ray)
end)

test("target death invalidates between frames", function()
    active.Settings.Method = "Mouse.Hit/Target"
    local candidate, head, humanoid = enemy("Target", 525, 390, 100)
    frame()
    humanoid.Health = 0
    equal(read("Hit"), originalResult)
end)

test("respawn invalidates old character immediately", function()
    active.Settings.Method = "Mouse.Hit/Target"
    local candidate, head = enemy("Target", 525, 390, 100)
    frame()
    makeCharacter(candidate, 526, 391, 100)
    equal(read("Hit"), originalResult)
    frame()
    equal(read("Target"), candidate.Character:FindFirstChild("Head"))
end)

test("player departure invalidates target", function()
    active.Settings.Method = "Mouse.Hit/Target"
    local candidate = enemy("Target", 525, 390, 100)
    frame()
    candidate.Parent = nil
    equal(read("Target"), originalResult)
end)

test("stale target expires", function()
    active.Settings.Method = "Mouse.Hit/Target"
    enemy("Target", 525, 390, 100)
    frame()
    active.UpdatedAt = os.clock() - 1
    equal(read("Hit"), originalResult)
end)

test("toggle and method keys ignore processed input", function()
    Input.InputBegan:Fire({ KeyCode = Enum.KeyCode.RightAlt }, true)
    equal(active.Settings.Enabled, true)
    Input.InputBegan:Fire({ KeyCode = Enum.KeyCode.RightAlt }, false)
    equal(active.Settings.Enabled, false)
    Input.InputBegan:Fire({ KeyCode = Enum.KeyCode.F6 }, false)
    equal(active.Settings.Method, "Mouse.Hit/Target")
end)

test("Unload removes UI and connections, leaves pass-through hooks", function()
    local gui = active.Gui
    active:Stop()
    active:Stop()
    equal(gui.Parent, nil)
    equal(Input.InputBegan:Count(), 0)
    equal(RunService.RenderStepped:Count(), 0)
    equal(read("Hit"), originalResult)
end)

test("reruns do not stack hooks or controls", function()
    local previous = active
    local count = hookCount
    active = launch()
    equal(previous.Stopped, true)
    equal(hookCount, count)
    equal(Input.InputBegan:Count(), 1)
    equal(RunService.RenderStepped:Count(), 1)
    equal(#playerGui._children, 1)
end)

test("hook errors disable redirection and preserve original call", function()
    active.Settings.Method = "Mouse.Hit/Target"
    active.Read = function() error("simulated error") end
    equal(read("Hit"), originalResult)
    equal(active.Settings.Enabled, false)
    assert(string.find(active.Status, "simulated error", 1, true))
end)

test("invalid numeric settings stop safely", function()
    active.Settings.Radius = 0 / 0
    frame()
    equal(active.Stopped, true)
    equal(RunService.RenderStepped:Count(), 0)
end)

test("no getnamecallmethod falls back to mouse mode", function()
    local original = getnamecallmethod
    getnamecallmethod = nil
    active = launch()
    getnamecallmethod = original
    equal(active.Settings.Method, "Mouse.Hit/Target")
end)

test("missing hook API fails before replacing active runtime", function()
    local original = hookmetamethod
    hookmetamethod = nil
    local ok, message = pcall(launch)
    hookmetamethod = original
    equal(ok, false)
    assert(string.find(message, "hookmetamethod is unavailable", 1, true))
    equal(active.Stopped, false)
end)

test("local death stops redirection between frames", function()
    active.Settings.Method = "Mouse.Hit/Target"
    enemy("Target", 525, 390, 100)
    frame()
    localPlayer.Character:FindFirstChildOfClass("Humanoid").Health = 0
    equal(read("Target"), originalResult)
end)

test("unequipping stops redirection between frames", function()
    active.Settings.Method = "Mouse.Hit/Target"
    enemy("Target", 525, 390, 100)
    frame()
    localPlayer.Character:FindFirstChildOfClass("Tool"):Destroy()
    equal(read("Target"), originalResult)
end)

test("locked mouse uses viewport center", function()
    Input.Pointer = Vector2.new(0, 0)
    Input.MouseBehavior = Enum.MouseBehavior.LockCenter
    enemy("Target", 525, 390, 100)
    frame()
    assert(active.Target)
end)

test("GUI destruction unloads runtime", function()
    active.Gui:Destroy()
    frame()
    equal(active.Stopped, true)
    equal(Input.InputBegan:Count(), 0)
end)

test("GUI Activated buttons toggle and unload", function()
    frame()
    local panel = active.Gui._children[2]
    local toggle, unload
    for _, child in ipairs(panel._children) do
        if child.ClassName == "TextButton" then
            if child.Text == "Enabled" then toggle = child end
            if child.Text == "Unload" then unload = child end
        end
    end
    assert(toggle and unload)
    equal(toggle.Modal, false)
    toggle.Activated:Fire()
    equal(active.Settings.Enabled, false)
    unload.Activated:Fire()
    equal(active.Stopped, true)
end)

test("first initialization without namecall capability", function()
    active:Stop()
    environment = {}
    hooks = {}
    local original = getnamecallmethod
    getnamecallmethod = nil
    active = launch()
    getnamecallmethod = original
    equal(hooks.__namecall, nil)
    equal(active.Settings.Method, "Mouse.Hit/Target")
    local candidate, head = enemy("Target", 525, 390, 100)
    frame()
    equal(read("Target"), head)
end)

test("UI initialization failure leaves inactive pass-through hooks", function()
    playerGui.Parent = nil
    local ok, message = pcall(launch)
    playerGui.Parent = localPlayer
    equal(ok, false)
    assert(string.find(message, "Control setup failed", 1, true))
    equal(environment.__IDERR_SilentAim_Bridge_v1.Active, nil)
    equal(read("Target"), originalResult)
end)

test("partial hook installation failure is explicit and blocks retry", function()
    active:Stop()
    environment = {}
    hooks = {}
    local original = hookmetamethod
    hookmetamethod = function(target, name, callback)
        if name == "__namecall" then error("simulated installation failure") end
        return original(target, name, callback)
    end
    local ok, message = pcall(launch)
    hookmetamethod = original
    equal(ok, false)
    assert(string.find(message, "Hook installation failed", 1, true))
    equal(read("Target"), originalResult)
    local retryOK, retryMessage = pcall(launch)
    equal(retryOK, false)
    assert(string.find(retryMessage, "Start a fresh session", 1, true))
end)

active:Stop()
print(tostring(total) .. " mocked behavior tests passed")
