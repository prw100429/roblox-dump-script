-- Client-visible instance structure only. No source or server-only data.
-- writefile/readfile are optional executor APIs, not Roblox APIs.
local ROOT = game
local MAX_NODES = 100000
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Run this on the Roblox client.")
local parent = player:WaitForChild("PlayerGui", 10)
assert(parent, "PlayerGui is unavailable.")
local UI_NAME = "RobloxStructureDumpUI_v2"
local old = parent:FindFirstChild(UI_NAME)
if old then old:Destroy() end

local function make(class, properties, container)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = container
    return object
end
local gui = make("ScreenGui", {Name = UI_NAME, ResetOnSpawn = false, DisplayOrder = 1000}, parent)
local panel = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.9, 0, 0, 370), BackgroundColor3 = Color3.fromRGB(24, 28, 38),
    BorderSizePixel = 0, Active = true,
}, gui)
make("UISizeConstraint", {MaxSize = Vector2.new(560, 370)}, panel)
make("UICorner", {CornerRadius = UDim.new(0, 12)}, panel)
local function label(text, y, height, size)
    return make("TextLabel", {
        Text = text, Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, height),
        BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(231, 237, 248),
        Font = Enum.Font.Gotham, TextSize = size or 14, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
end
label("게임 구조 덤프", 14, 30, 22)
local status = label("준비 중", 55, 34, 17)
local detail = label("", 94, 40)
local track = make("Frame", {
    Position = UDim2.new(0, 20, 0, 146), Size = UDim2.new(1, -40, 0, 16),
    BackgroundColor3 = Color3.fromRGB(49, 57, 72), BorderSizePixel = 0,
}, panel)
local fill = make("Frame", {
    Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(74, 163, 255), BorderSizePixel = 0,
}, track)
local percentage = label("목록 수집 후 처리 비율을 표시합니다.", 169, 24)
local note = label("클라이언트에서 보이는 오브젝트만 저장합니다.", 198, 40, 13)
local output = make("TextBox", {
    Position = UDim2.new(0, 20, 0, 245), Size = UDim2.new(1, -40, 0, 58),
    Text = "저장된 파일 이름이 여기에 표시됩니다.", ClearTextOnFocus = false,
    MultiLine = true, TextWrapped = true, TextSize = 12, Font = Enum.Font.Code,
    TextColor3 = Color3.fromRGB(216, 229, 248), BackgroundColor3 = Color3.fromRGB(15, 19, 28),
}, panel)
local function button(text, x)
    return make("TextButton", {
        Text = text, Position = UDim2.new(x, x == 0 and 20 or 4, 0, 320),
        Size = UDim2.new(0.5, -24, 0, 34), TextSize = 14, Font = Enum.Font.Gotham,
        TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(48, 82, 125),
    }, panel)
end
local startButton = button("덤프 시작", 0)
local stopButton = button("닫기", 0.5)
local running, cancelled, alive, phase = false, false, true, "idle"
gui.Destroying:Connect(function() alive = false; cancelled = true end)
local function checkpoint()
    if cancelled or not alive then error("DUMP_CANCELLED", 0) end
end
local function refresh(text, info, ratio)
    if not alive then return end
    status.Text = text
    detail.Text = info or ""
    if ratio then fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) end
end
local function yieldUI()
    task.wait()
    checkpoint()
end

local function dump()
    assert(type(writefile) == "function", "이 실행기는 writefile을 지원하지 않습니다.")
    local started = os.clock()
    local entries = {{object = ROOT, parentId = 0}}
    local seen = {[ROOT] = true}
    local warnings, nodes = {}, {}
    local truncated = false
    local cursor, work = 1, 0
    phase = "collect"
    percentage.Text = "수집 중 · 전체 개수 확인 전"
    refresh("1/3 · 대상 목록 수집 중", "발견한 오브젝트: 1개", 0)
    yieldUI()
    while cursor <= #entries do
        checkpoint()
        local object = entries[cursor].object
        local ok, children = pcall(function() return object:GetChildren() end)
        if ok then
            for _, child in ipairs(children) do
                local inspected, skip = pcall(function()
                    return child == gui or (object == game and (child.ClassName == "CoreGui" or child.Name == "CorePackages"))
                end)
                if not inspected then
                    warnings[#warnings + 1] = "Could not inspect a child of node " .. cursor
                elseif not skip and not seen[child] then
                    if #entries >= MAX_NODES then truncated = true; break end
                    seen[child] = true
                    entries[#entries + 1] = {object = child, parentId = cursor}
                end
                work = work + 1
                if work % 200 == 0 then
                    refresh("1/3 · 대상 목록 수집 중", string.format("발견 %d개 · 탐색 %d개", #entries, cursor))
                    yieldUI()
                end
            end
        else
            warnings[#warnings + 1] = "Cannot read children of node " .. cursor .. ": " .. tostring(children)
        end
        if truncated then break end
        cursor = cursor + 1
        if cursor % 200 == 0 then
            refresh("1/3 · 대상 목록 수집 중", string.format("발견 %d개 · 탐색 %d개", #entries, cursor - 1))
            yieldUI()
        end
    end
    phase = "process"
    local total = #entries
    for id, entry in ipairs(entries) do
        checkpoint()
        local ok, name, className = pcall(function() return entry.object.Name, entry.object.ClassName end)
        nodes[id] = {
            id = id, parentId = entry.parentId,
            name = ok and name or "<unreadable>", className = ok and className or "Unknown",
        }
        if not ok then warnings[#warnings + 1] = "Cannot read node " .. id .. ": " .. tostring(name) end
        if id % 200 == 0 or id == total then
            local ratio = id / total
            percentage.Text = string.format("오브젝트 처리 %.1f%%", ratio * 100)
            refresh("2/3 · 구조 데이터 처리 중", string.format("%d / %d개 · 경고 %d개", id, total, #warnings), ratio)
            yieldUI()
        end
    end
    local payload = {
        format = "roblox-structure-dump", version = 1, scope = "client-visible",
        createdAt = DateTime.now():ToIsoDate(), placeId = game.PlaceId,
        nodeCount = #nodes, truncated = truncated, warnings = warnings,
        excluded = {"game.CoreGui", "game.CorePackages", "dump UI"}, nodes = nodes,
    }
    phase = "encode"
    refresh("3/3 · JSON 변환 중", "오브젝트 처리 완료 · 파일 저장 대기")
    note.Text = "JSON 변환·파일 쓰기는 세부 진행률을 제공하지 않습니다."
    yieldUI()
    local json = HttpService:JSONEncode(payload)
    checkpoint()
    local filename = "roblox-structure-" .. tostring(game.PlaceId) .. "-" .. HttpService:GenerateGUID(false) .. ".json"
    refresh("3/3 · 파일 저장 중", string.format("%.2f MB · 저장 함수의 완료를 기다리는 중", #json / 1048576))
    -- Cancellation is accepted up to the last checkpoint before writefile.
    yieldUI()
    phase = "save"
    stopButton.Text = "저장 중"
    writefile(filename, json)
    if not alive then return end
    output.Text = filename
    phase = "verify"
    refresh("3/3 · 저장 결과 확인 중", "파일 쓰기 함수가 성공을 반환했습니다.")
    task.wait()
    if not alive then return end
    local verification = "저장 함수 성공 · 재읽기 확인 미지원"
    local verified = false
    if type(readfile) == "function" then
        local readOK, content = pcall(function() return readfile(filename) end)
        if not readOK then
            fill.BackgroundColor3 = Color3.fromRGB(244, 179, 68)
            refresh("저장 후 확인 실패", "파일 쓰기는 완료됐지만 재읽기에 실패했습니다.")
            note.Text = tostring(content)
            percentage.Text = "오브젝트 처리 100% · 파일 확인 필요"
            return
        elseif content ~= json then
            error("저장된 파일 내용이 원본과 다릅니다. 표시된 파일을 확인하세요.", 0)
        end
        verification = "파일을 다시 읽어 내용 일치 확인"
        verified = true
    end
    local partial = truncated or #warnings > 0
    fill.BackgroundColor3 = partial and Color3.fromRGB(244, 179, 68) or Color3.fromRGB(75, 207, 139)
    percentage.Text = verified and "완료 100% · 파일 내용 확인됨" or "처리 100% · 저장 함수 성공"
    refresh(partial and "저장 완료 · 일부 누락 가능" or "저장 완료", string.format("%d개 · %.2f MB · %.1f초", #nodes, #json / 1048576, os.clock() - started), 1)
    note.Text = verification .. (truncated and " / 개수 한도 도달" or "") .. string.format(" / 경고 %d개", #warnings)
    print("Dump saved: " .. filename)
end

startButton.Activated:Connect(function()
    if running or not alive then return end
    running, cancelled, phase = true, false, "collect"
    startButton.Text = "진행 중…"
    stopButton.Text = "취소"
    output.Text = "아직 저장되지 않았습니다."
    note.Text = "실행기 저장 폴더에 JSON 파일을 만듭니다."
    fill.BackgroundColor3 = Color3.fromRGB(74, 163, 255)
    task.spawn(function()
        local ok, message = pcall(dump)
        if not alive then return end
        running = false
        startButton.Text = "다시 실행"
        stopButton.Text = "닫기"
        if not ok then
            if cancelled then
                refresh("취소됨", "이번 실행에서는 파일을 저장하지 않았습니다.")
                percentage.Text = "취소됨"
            else
                fill.BackgroundColor3 = Color3.fromRGB(238, 91, 106)
                refresh("실패 · 오류 확인", "아래 오류 내용을 확인해 주세요.")
                note.Text = tostring(message)
                output.Text = output.Text .. "\n오류: " .. tostring(message)
                percentage.Text = "실패 단계: " .. phase
                warn("Dump failed: " .. tostring(message))
            end
        end
        phase = "idle"
    end)
end)
stopButton.Activated:Connect(function()
    if running then
        if phase == "save" or phase == "verify" then return end
        cancelled = true
        stopButton.Text = "취소 중…"
    else
        gui:Destroy()
    end
end)
refresh("준비 완료", "‘덤프 시작’을 누르면 진행 상태를 표시합니다.", 0)
if type(writefile) ~= "function" then
    refresh("파일 저장 미지원", "이 실행기에는 writefile 함수가 없습니다.")
    note.Text = "시작해도 파일을 저장할 수 없습니다."
end
