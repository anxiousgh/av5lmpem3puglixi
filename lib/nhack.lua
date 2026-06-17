--[[
    2/22/2026
    Library.lua
    Purpose:
        NH ui library

    Author: @joestar._3
    Dependencies:
        None
]]

-- hi guys

if getgenv().Library and getgenv().Library.Exit then
    getgenv().Library:Exit()
end

-- Bad executor support (atleast by a bit)
cloneref = cloneref or function(Object) return Object end

--#region Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui = cloneref(game:GetService("CoreGui"))
local GuiService = game:GetService("GuiService")
--#endregion

gethui = gethui or function() return CoreGui end

--#region Variables
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = cloneref(LocalPlayer:GetMouse())
local GuiInset = GuiService:GetGuiInset().Y
local BlockedWindowInputs = {
    Enum.KeyCode.W,
    Enum.KeyCode.A,
    Enum.KeyCode.S,
    Enum.KeyCode.D,
    Enum.KeyCode.Space,
    Enum.KeyCode.LeftShift,
    Enum.KeyCode.RightShift,
    Enum.KeyCode.LeftControl,
    Enum.KeyCode.RightControl,
    Enum.KeyCode.LeftAlt,
    Enum.KeyCode.RightAlt,
    Enum.KeyCode.Up,
    Enum.KeyCode.Down,
    Enum.KeyCode.Left,
    Enum.KeyCode.Right,
    Enum.KeyCode.Return,
    Enum.KeyCode.KeypadEnter,
    Enum.KeyCode.Slash,
    Enum.KeyCode.Backquote,
    Enum.KeyCode.Tab,
    Enum.KeyCode.E,
    Enum.KeyCode.Q,
    Enum.KeyCode.R,
    Enum.KeyCode.F,
    Enum.KeyCode.C,
    Enum.KeyCode.Z,
    Enum.KeyCode.X,
    Enum.KeyCode.One,
    Enum.KeyCode.Two,
    Enum.KeyCode.Three,
    Enum.KeyCode.Four,
    Enum.KeyCode.Five,
    Enum.KeyCode.Six,
    Enum.KeyCode.Seven,
    Enum.KeyCode.Eight,
    Enum.KeyCode.Nine,
    Enum.KeyCode.Zero
}
--#endregion

local Library = {
    Flags = {},
    MenuKeybind = tostring(Enum.KeyCode.X),

    Directory = "niggahack",
    Folders = {
        Assets = "/Assets",
        Configs = "/Configs"
    },

    FontSize = 9,

    Animation = {
        Time = 0.3,
        Style = "Quint",
        Direction = "Out"
    },

    Theme = nil,

    -- Ignore below
    Threads = {},
    Connections = {},
    Notifications = {},
    SetFlags = {},

    ThemingStuff = {},
    ThemeMap = {},

    OpenFrames = {},
    WindowVisibilityBindings = {},
    WindowOpenState = true,
    InputBlockAction = "NH_UI_INPUT_BLOCK",
    BackgroundEffects = nil,
    BackgroundBlurEnabled = true,
    BackgroundSnowEnabled = true,
    CopiedColor = nil,
    LayoutRegistry = {},
    SettingsWidgets = {},
    ActiveConfirmDialog = nil,
    MouseCursor = nil,
    MouseStateBeforeOpen = nil,

    Holder = nil,
    UnusedHolder = nil,

    Font = nil
}
do
    Library.__index = Library

    local Flags = Library.Flags
    local SetFlags = Library.SetFlags

    local Keys = {
        ["Unknown"]          = "Unknown",
        ["Backspace"]        = "Back",
        ["Tab"]              = "Tab",
        ["Clear"]            = "Clear",
        ["Return"]           = "Return",
        ["Pause"]            = "Pause",
        ["Escape"]           = "Escape",
        ["Space"]            = "Space",
        ["QuotedDouble"]     = '"',
        ["Hash"]             = "#",
        ["Dollar"]           = "$",
        ["Percent"]          = "%",
        ["Ampersand"]        = "&",
        ["Quote"]            = "'",
        ["LeftParenthesis"]  = "(",
        ["RightParenthesis"] = " )",
        ["Asterisk"]         = "*",
        ["Plus"]             = "+",
        ["Comma"]            = ",",
        ["Minus"]            = "-",
        ["Period"]           = ".",
        ["Slash"]            = "`",
        ["Three"]            = "3",
        ["Seven"]            = "7",
        ["Eight"]            = "8",
        ["Colon"]            = ":",
        ["Semicolon"]        = ";",
        ["LessThan"]         = "<",
        ["GreaterThan"]      = ">",
        ["Question"]         = "?",
        ["Equals"]           = "=",
        ["At"]               = "@",
        ["LeftBracket"]      = "LeftBracket",
        ["RightBracket"]     = "RightBracked",
        ["BackSlash"]        = "BackSlash",
        ["Caret"]            = "^",
        ["Underscore"]       = "_",
        ["Backquote"]        = "`",
        ["LeftCurly"]        = "{",
        ["Pipe"]             = "|",
        ["RightCurly"]       = "}",
        ["Tilde"]            = "~",
        ["Delete"]           = "Delete",
        ["End"]              = "End",
        ["KeypadZero"]       = "Keypad0",
        ["KeypadOne"]        = "Keypad1",
        ["KeypadTwo"]        = "Keypad2",
        ["KeypadThree"]      = "Keypad3",
        ["KeypadFour"]       = "Keypad4",
        ["KeypadFive"]       = "Keypad5",
        ["KeypadSix"]        = "Keypad6",
        ["KeypadSeven"]      = "Keypad7",
        ["KeypadEight"]      = "Keypad8",
        ["KeypadNine"]       = "Keypad9",
        ["KeypadPeriod"]     = "KeypadP",
        ["KeypadDivide"]     = "KeypadD",
        ["KeypadMultiply"]   = "KeypadM",
        ["KeypadMinus"]      = "KeypadM",
        ["KeypadPlus"]       = "KeypadP",
        ["KeypadEnter"]      = "KeypadE",
        ["KeypadEquals"]     = "KeypadE",
        ["Insert"]           = "Insert",
        ["Home"]             = "Home",
        ["PageUp"]           = "PageUp",
        ["PageDown"]         = "PageDown",
        ["RightShift"]       = "RightShift",
        ["LeftShift"]        = "LeftShift",
        ["RightControl"]     = "RightControl",
        ["LeftControl"]      = "LeftControl",
        ["LeftAlt"]          = "LeftAlt",
        ["RightAlt"]         = "RightAlt"
    }

    -- Folders
    if not isfolder(Library.Directory) then
        makefolder(Library.Directory)
    end

    for _, Folder in Library.Folders do
        if not isfolder(Library.Directory .. Folder) then
            makefolder(Library.Directory .. Folder)
        end
    end

    local Themes = {
        ["Preset"] = {
            ["Background"] = Color3.fromRGB(16, 17, 20),
            ["Outline"] = Color3.fromRGB(36, 38, 45),
            ["Border"] = Color3.fromRGB(7, 8, 10),
            ["Accent"] = Color3.fromRGB(152, 188, 255),
            ["Risky"] = Color3.fromRGB(255, 50, 50),
            ["Light Border"] = Color3.fromRGB(12, 8, 12),
            ["Border 2"] = Color3.fromRGB(5, 10, 14),
            ["Text"] = Color3.fromRGB(180, 180, 180),
            ["Section"] = Color3.fromRGB(20, 21, 25),
            ["Element"] = Color3.fromRGB(28, 29, 35),
            ["Hovered Element"] = Color3.fromRGB(36, 38, 45),
            ["Inactive Text"] = Color3.fromRGB(100, 100, 100)
        }
    }

    Library.Theme = Themes.Preset

    -- Custom Font
    local CustomFont = {}
    do
        function CustomFont:New(Name, Weight, Style, Data)
            if not isfile(Data.Id) then
                writefile(Data.Id, game:HttpGet(Data.Url))
            end

            local Data = {
                name = Name,
                faces = {
                    {
                        name = Name,
                        weight = Weight,
                        style = Style,
                        assetId = getcustomasset(Data.Id)
                    }
                }
            }

            writefile(`{Library.Directory .. Library.Folders.Assets}/{Name}.font`, HttpService:JSONEncode(Data))
            return Font.new(getcustomasset(`{Library.Directory .. Library.Folders.Assets}/{Name}.font`))
        end

        Library.Font = CustomFont:New("SmallestPixel7", 400, "Regular", {
            Id = "SmallestPixel7",
            Url = "https://github.com/sametexe001/luas/raw/refs/heads/main/smallest_pixel-7.ttf"
        })
    end

    Library.Exit = function(Self)
        Self:ApplyWindowInputState(false)

        if Self.BackgroundEffects then
            Self.BackgroundEffects.IsSnowing = false

            if Self.BackgroundEffects.BlurEffect and Self.BackgroundEffects.BlurEffect.Parent then
                Self.BackgroundEffects.BlurEffect:Destroy()
            end

            if Self.BackgroundEffects.Background and Self.BackgroundEffects.Background.Parent then
                Self.BackgroundEffects.Background:Destroy()
            end
        end

        for _, Connection in Library.Connections do
            Connection:Disconnect()
        end

        for _, Thread in Library.Threads do
            coroutine.close(Thread)
        end

        if Self.Holder then
            Self.Holder.Instance:Destroy()
        end

        if Self.UnusedHolder then
            Self.UnusedHolder.Instance:Destroy()
        end

        Library = nil
        getgenv().Library = nil
    end

    Library.Create = function(Self, Class, Properties)
        local Data = {
            Class = Class,
            Properties = Properties,
            Instance = Instance.new(Class)
        }

        for Index, Property in Properties do
            if Property == "FontFace" then
                Data.Instance[Property] = Library.Font
                continue
            end

            if Property == "TextSize" then
                Data.Instance[Property] = Library.FontSize
                continue
            end

            if Property == "Name" then
                Data.Instance[Property] = "\0"
                continue
            end

            if Class == "TextButton" then
                if Property == "AutoButtonColor" then
                    Data.Instance[Property] = false
                    continue
                end

                if Property == "Text" then
                    Data.Instance[Property] = ""
                    continue
                end
            end

            Data.Instance[Index] = Property
        end

        return setmetatable(Data, Library)
    end

    Library.Thread = function(Self, Function)
        local NewThread = coroutine.create(Function)

        coroutine.wrap(function()
            coroutine.resume(NewThread)
        end)()

        table.insert(Library.Threads, NewThread)
        return NewThread
    end

    Library.Connect = function(Self, Signal, Callback)
        local Connection

        if Self.Instance then
            if Self.Instance[Signal] then
                Connection = Self.Instance[Signal]:Connect(Callback)
            else
                Connection = Signal:Connect(Callback)
            end
        else
            Connection = Signal:Connect(Callback)
        end

        table.insert(Library.Connections, Connection)
        return Connection
    end

    Library.Tween = function(Self, Properties, Info, IsRawItem)
        local Object = Self.Instance or IsRawItem
        Info = Info or
            TweenInfo.new(Library.Animation.Time, Enum.EasingStyle[Library.Animation.Style],
                Enum.EasingDirection[Library.Animation.Direction])

        if not Object then
            return
        end

        local NewTween = TweenService:Create(Object, Info, Properties)
        NewTween:Play()

        return NewTween
    end

    Library.GetTweenProperty = function(Self, IsRawItem)
        local Object = Self.Instance or IsRawItem

        if not Object then
            return {}
        end

        if Object:IsA("Frame") then
            return { "BackgroundTransparency" }
        elseif Object:IsA("TextLabel") or Object:IsA("TextButton") then
            return { "TextTransparency", "BackgroundTransparency" }
        elseif Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
            return { "BackgroundTransparency", "ImageTransparency" }
        elseif Object:IsA("ScrollingFrame") then
            return { "BackgroundTransparency", "ScrollBarImageTransparency" }
        elseif Object:IsA("TextBox") then
            return { "TextTransparency", "BackgroundTransparency" }
        elseif Object:IsA("UIStroke") then
            return { "Transparency" }
        end
    end

    Library.Fade = function(Self, Property, Visibility, IsRawItem)
        local Object = Self.Instance or IsRawItem

        if not Object then
            return
        end

        local OldTransparency = Object[Property]
        Object[Property] = Visibility and 1 or OldTransparency

        local NewTween = Library:Tween({
            [Property] = Visibility and OldTransparency or 1
        }, nil, Object)

        Library:Connect(NewTween.Completed, function()
            if not Visibility then
                task.wait()
                Object[Property] = OldTransparency
            end
        end)

        return NewTween
    end

    Library.FadeDescendants = function(Self, Visibility, Callback)
        if Visibility then
            Self.Instance.Visible = true
        end

        local NewTween

        local Children = Self.Instance:GetDescendants()
        table.insert(Children, Self.Instance)

        for _, Child in Children do
            local TransparencyProperty = Library:GetTweenProperty(Child)

            if not TransparencyProperty then
                continue
            end

            if type(TransparencyProperty) == "table" then
                for _, Property in TransparencyProperty do
                    NewTween = Library:Fade(Property, Visibility, Child)
                end
            else
                NewTween = Library:Fade(TransparencyProperty, Visibility, Child)
            end
        end

        Library:Connect(NewTween.Completed, function()
            if Callback and type(Callback) == "function" then
                Callback()
            end

            Self.Instance.Visible = Visibility
        end)
    end

    Library.MakeDraggable = function(Self)
        if not Self.Instance then
            return
        end

        local Gui = Self.Instance
        local Dragging = false
        local DragStart
        local StartPosition

        local Set = function(Input)
            local DragDelta = Input.Position - DragStart
            local NewX = StartPosition.X.Offset + DragDelta.X
            local NewY = StartPosition.Y.Offset + DragDelta.Y

            local ScreenSize = Gui.Parent.AbsoluteSize
            local GuiSize = Gui.AbsoluteSize

            NewX = math.clamp(NewX, 0, ScreenSize.X - GuiSize.X)
            NewY = math.clamp(NewY, 0, ScreenSize.Y - GuiSize.Y)

            local MainWindow = Library.MainWindowFrame
            if Gui ~= MainWindow
                and Library.WindowOpenState
                and MainWindow
                and MainWindow.Parent == Gui.Parent
                and MainWindow.Visible
            then
                local PanelPosition = MainWindow.AbsolutePosition
                local PanelSize = MainWindow.AbsoluteSize
                local PanelLeft = PanelPosition.X
                local PanelTop = PanelPosition.Y
                local PanelRight = PanelLeft + PanelSize.X
                local PanelBottom = PanelTop + PanelSize.Y

                local OverlapsX = (NewX < PanelRight) and ((NewX + GuiSize.X) > PanelLeft)
                local OverlapsY = (NewY < PanelBottom) and ((NewY + GuiSize.Y) > PanelTop)

                if OverlapsX and OverlapsY then
                    local LeftGap = math.abs((NewX + GuiSize.X) - PanelLeft)
                    local RightGap = math.abs(NewX - PanelRight)
                    local TopGap = math.abs((NewY + GuiSize.Y) - PanelTop)
                    local BottomGap = math.abs(NewY - PanelBottom)
                    local MinGap = math.min(LeftGap, RightGap, TopGap, BottomGap)

                    if MinGap == LeftGap then
                        NewX = PanelLeft - GuiSize.X
                    elseif MinGap == RightGap then
                        NewX = PanelRight
                    elseif MinGap == TopGap then
                        NewY = PanelTop - GuiSize.Y
                    else
                        NewY = PanelBottom
                    end
                end
            end

            Gui.Position = UDim2.new(0, math.floor(NewX + 0.5), 0, math.floor(NewY + 0.5))
        end

        local InputChanged

        Self:Connect("InputBegan", function(Input)
            if not Library.WindowOpenState then
                return
            end

            if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                Dragging = true
                DragStart = Input.Position
                StartPosition = Gui.Position

                if InputChanged then
                    return
                end

                InputChanged = Input.Changed:Connect(function()
                    if Input.UserInputState == Enum.UserInputState.End then
                        Dragging = false
                        InputChanged:Disconnect()
                        InputChanged = nil
                    end
                end)
            end
        end)

        Library:Connect(UserInputService.InputChanged, function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
                if Dragging and not Library.WindowOpenState then
                    Dragging = false
                    return
                end

                if Dragging then
                    Set(Input)
                end
            end
        end)

        return Dragging
    end

    Library.MakeResizeable = function(Self, Minimum)
        if not Self.Instance then
            return
        end

        local Gui = Self.Instance

        local Resizing = false
        local CurrentSide = nil

        local StartMouse = nil
        local StartPosition = nil
        local StartSize = nil

        local EdgeThickness = 2

        local MakeEdge = function(Name, Position, Size)
            local Button = Library:Create("TextButton", {
                Name = "\0",
                Size = Size,
                Position = Position,
                BackgroundColor3 = Color3.fromRGB(166, 147, 243),
                BackgroundTransparency = 1,
                Text = "",
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Parent = Gui,
                ZIndex = 99999,
            })
            Button:AddToTheme({ BackgroundColor3 = "Accent" })

            return Button
        end

        local Edges = {
            {
                Button = MakeEdge(
                    "Left",
                    UDim2.new(0, 0, 0, 0),
                    UDim2.new(0, EdgeThickness, 1, 0)),
                Side = "L"
            },

            {
                Button = MakeEdge(
                    "Right",
                    UDim2.new(1, -EdgeThickness, 0, 0),
                    UDim2.new(0, EdgeThickness, 1, 0)),
                Side = "R"
            },

            {
                Button = MakeEdge(
                    "Top", UDim2.new(0, 0, 0, 0),
                    UDim2.new(1, 0, 0, EdgeThickness)),
                Side = "T"
            },

            {
                Button = MakeEdge(
                    "Bottom",
                    UDim2.new(0, 0, 1, -EdgeThickness),
                    UDim2.new(1, 0, 0, EdgeThickness)),
                Side = "B"
            },
        }

        local BeginResizing = function(Side)
            Resizing = true
            CurrentSide = Side

            StartMouse = UserInputService:GetMouseLocation()

            StartPosition = Vector2.new(Gui.Position.X.Offset, Gui.Position.Y.Offset)
            StartSize = Vector2.new(Gui.Size.X.Offset, Gui.Size.Y.Offset)

            for Index, Value in Edges do
                Value.Button.Instance.BackgroundTransparency = (Value.Side == Side) and 0 or 1
            end
        end

        local EndResizing = function()
            Resizing = false
            CurrentSide = nil

            for Index, Value in Edges do
                Value.Button.Instance.BackgroundTransparency = 1
            end
        end

        for Index, Value in Edges do
            Value.Button:Connect("InputBegan", function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    BeginResizing(Value.Side)
                end
            end)
        end

        Library:Connect(UserInputService.InputEnded, function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                if Resizing then
                    EndResizing()
                end
            end
        end)

        Library:Connect(RunService.RenderStepped, function()
            if not Resizing or not CurrentSide then
                return
            end

            local MouseLocation = UserInputService:GetMouseLocation()
            local dx = MouseLocation.X - StartMouse.X
            local dy = MouseLocation.Y - StartMouse.Y

            local x, y = StartPosition.X, StartPosition.Y
            local w, h = StartSize.X, StartSize.Y

            if CurrentSide == "L" then
                x = StartPosition.X + dx
                w = StartSize.X - dx
            elseif CurrentSide == "R" then
                w = StartSize.X + dx
            elseif CurrentSide == "T" then
                y = StartPosition.Y + dy
                h = StartSize.Y - dy
            elseif CurrentSide == "B" then
                h = StartSize.Y + dy
            end

            if w < Minimum.X then
                if CurrentSide == "L" then
                    x = x - (Minimum.X - w)
                end
                w = Minimum.X
            end
            if h < Minimum.Y then
                if CurrentSide == "T" then
                    y = y - (Minimum.Y - h)
                end
                h = Minimum.Y
            end

            Self:Tween({ Position = UDim2.fromOffset(x, y) },
                TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
            Self:Tween({ Size = UDim2.fromOffset(w, h) },
                TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
        end)
    end

    Library.IsMouseOverFrame = function(Self)
        if not Self.Instance then
            return
        end

        local Object = Self.Instance

        local MousePosition = Vector2.new(Mouse.X, Mouse.Y)

        return MousePosition.X >= Object.AbsolutePosition.X and
            MousePosition.X <= Object.AbsolutePosition.X + Object.AbsoluteSize.X
            and MousePosition.Y >= Object.AbsolutePosition.Y and
            MousePosition.Y <= Object.AbsolutePosition.Y + Object.AbsoluteSize.Y
    end

    Library.CompareVectors = function(Self, PointA, PointB)
        return (PointA.X < PointB.X) or (PointA.Y < PointB.Y)
    end

    Library.IsClipped = function(Self, Column)
        if not Self.Instance then
            return
        end

        local Parent = Column
        local Object = Self.Instance

        local BoundryTop = Parent.AbsolutePosition
        local BoundryBottom = BoundryTop + Parent.AbsoluteSize

        local Top = Object.AbsolutePosition
        local Bottom = Top + Object.AbsoluteSize

        return Library:CompareVectors(Top, BoundryTop) or Library:CompareVectors(BoundryBottom, Bottom)
    end

    Library.SafeCall = function(Self, Function, ...)
        local Arguements = { ... }
        local Success, Result = pcall(Function, table.unpack(Arguements))

        if not Success then
            warn(Result)
            return false
        end

        return Success, Result
    end

    Library.BindToWindowVisibility = function(Self, Callback)
        if type(Callback) ~= "function" then
            return
        end

        table.insert(Library.WindowVisibilityBindings, Callback)
        Library:SafeCall(Callback, Library.WindowOpenState)
    end

    Library.ApplyWindowInputState = function(Self, Bool)
        if Self.InputBlocker and Self.InputBlocker.Instance then
            Self.InputBlocker.Instance.Visible = Bool and true or false
        end

        if Bool then
            ContextActionService:BindActionAtPriority(Self.InputBlockAction, function(_, State, Input)
                    if State ~= Enum.UserInputState.Begin and State ~= Enum.UserInputState.Change then
                        return Enum.ContextActionResult.Pass
                    end

                    if not Self.WindowOpenState or UserInputService:GetFocusedTextBox() then
                        return Enum.ContextActionResult.Pass
                    end

                    if Input and (tostring(Input.KeyCode) == Self.MenuKeybind or tostring(Input.UserInputType) == Self.MenuKeybind) then
                        return Enum.ContextActionResult.Pass
                    end

                    return Enum.ContextActionResult.Sink
                end, false, 5000,
                Enum.UserInputType.Gamepad1,
                Enum.UserInputType.Gamepad2,
                Enum.UserInputType.Gamepad3,
                Enum.UserInputType.Gamepad4,
                Enum.UserInputType.Gamepad5,
                Enum.UserInputType.Gamepad6,
                Enum.UserInputType.Gamepad7,
                Enum.UserInputType.Gamepad8,
                Enum.UserInputType.MouseWheel,
                Enum.UserInputType.MouseButton2,
                Enum.UserInputType.MouseButton3
            )

            ContextActionService:BindActionAtPriority(Self.InputBlockAction .. "_KEYS", function(_, State)
                if State ~= Enum.UserInputState.Begin and State ~= Enum.UserInputState.Change then
                    return Enum.ContextActionResult.Pass
                end

                if not Self.WindowOpenState or UserInputService:GetFocusedTextBox() then
                    return Enum.ContextActionResult.Pass
                end

                return Enum.ContextActionResult.Sink
            end, false, 5000, table.unpack(BlockedWindowInputs))
            return
        end

        ContextActionService:UnbindAction(Self.InputBlockAction)
        ContextActionService:UnbindAction(Self.InputBlockAction .. "_KEYS")
    end

    Library.SetWindowVisibilityState = function(Self, Bool)
        Library.WindowOpenState = Bool and true or false
        Library:ApplyWindowInputState(Library.WindowOpenState)

        if Library.WindowOpenState then
            Library.MouseStateBeforeOpen = {
                MouseBehavior = UserInputService.MouseBehavior,
                MouseIconEnabled = UserInputService.MouseIconEnabled,
            }
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = false
        elseif Library.MouseStateBeforeOpen then
            UserInputService.MouseBehavior = Library.MouseStateBeforeOpen.MouseBehavior or Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = Library.MouseStateBeforeOpen.MouseIconEnabled ~= false
            Library.MouseStateBeforeOpen = nil
        else
            UserInputService.MouseIconEnabled = true
        end

        if Library.MouseCursor and Library.MouseCursor.Instance then
            Library.MouseCursor.Instance.Visible = Library.WindowOpenState
        end

        if not Library.WindowOpenState then
            for _, OpenFrame in Library.OpenFrames do
                if OpenFrame and OpenFrame.IsOpen and OpenFrame.SetOpen then
                    OpenFrame:SetOpen(false)
                end
            end
        end

        for _, Callback in Library.WindowVisibilityBindings do
            Library:SafeCall(Callback, Library.WindowOpenState)
        end
    end

    Library.RegisterSettingsWidget = function(Self, Data)
        if type(Data) ~= "table" then
            return
        end

        local Name = Data.Name or Data.name
        local Callback = Data.Callback or Data.callback
        if type(Name) ~= "string" or type(Callback) ~= "function" then
            return
        end

        table.insert(Library.SettingsWidgets, {
            Name = Name,
            Flag = Data.Flag or Data.flag or ("UIWidget" .. Name:gsub("%s+", "")),
            Default = Data.Default ~= false,
            Callback = Callback,
            Settings = Data.Settings or Data.settings
        })
    end

    Library.SetupBackgroundEffects = function(Self)
        if Library.BackgroundEffects then
            return
        end

        local Background = Library:Create("Frame", {
            Name = "\0",
            Parent = Library.Holder.Instance,
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(1, 0, 1, 0),
            Visible = false,
            ZIndex = 0
        })

        local SnowHolder = Library:Create("Frame", {
            Name = "\0",
            Parent = Background.Instance,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 0
        })

        local BlurEffect = Instance.new("BlurEffect")
        BlurEffect.Size = 0
        BlurEffect.Parent = Camera

        Library.BackgroundEffects = {
            Background = Background.Instance,
            SnowHolder = SnowHolder.Instance,
            BlurEffect = BlurEffect,
            SnowAsset = "http://www.roblox.com/asset/?id=6871196088",
            IsSnowing = false
        }

        Library:Thread(function()
            while Library and Library.BackgroundEffects do
                local Effects = Library.BackgroundEffects

                if not Effects.IsSnowing then
                    task.wait(0.1)
                    continue
                end

                local Holder = Effects.SnowHolder
                if not Holder or not Holder.Parent then
                    task.wait(0.1)
                    continue
                end

                local Width = Holder.AbsoluteSize.X
                local Height = Holder.AbsoluteSize.Y
                if Width <= 0 or Height <= 0 then
                    task.wait(0.1)
                    continue
                end

                local Image = Instance.new("ImageLabel")
                Image.Name = "\0"
                Image.Parent = Holder
                Image.BackgroundTransparency = 1
                Image.Image = Effects.SnowAsset
                Image.ZIndex = 0

                local RandomSize = math.random(5, 8)
                local SpawnX = math.random(0, math.max(0, Width - RandomSize))

                Image.Size = UDim2.new(0, RandomSize, 0, RandomSize)
                Image.Position = UDim2.new(0, SpawnX, 0, -10)

                local FallDuration = math.random(20, 40) / 10
                local SwayX = math.random(-18, 18)
                local GoalPosition = UDim2.new(0, SpawnX + SwayX, 0, Height + 10)

                local FallTween = TweenService:Create(Image,
                    TweenInfo.new(FallDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
                        Position = GoalPosition,
                        ImageTransparency = 1
                    })

                FallTween:Play()
                Library:Connect(FallTween.Completed, function()
                    if Image and Image.Parent then
                        Image:Destroy()
                    end
                end)

                task.wait(0.1)
            end
        end)
    end

    Library.SetBackgroundEffectsVisible = function(Self, Bool, Instant)
        local Effects = Library.BackgroundEffects
        if not Effects then
            return
        end

        local HasAnyEffect = Library.BackgroundBlurEnabled or Library.BackgroundSnowEnabled
        local IsVisible = Bool and true or false
        Effects.IsSnowing = IsVisible and Library.BackgroundSnowEnabled

        local TargetTransparency = (IsVisible and HasAnyEffect) and 0.5 or 1
        local TargetBlur = (IsVisible and Library.BackgroundBlurEnabled) and 20 or 0

        if IsVisible and HasAnyEffect then
            Effects.Background.Visible = true
        end

        if Instant then
            Effects.Background.BackgroundTransparency = TargetTransparency
            Effects.BlurEffect.Size = TargetBlur
        else
            local FadeTween = TweenService:Create(Effects.Background,
                TweenInfo.new(0.33, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                    BackgroundTransparency = TargetTransparency
                })

            local BlurTween = TweenService:Create(Effects.BlurEffect,
                TweenInfo.new(0.33, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                    Size = TargetBlur
                })

            FadeTween:Play()
            BlurTween:Play()
        end

        if (not IsVisible) or (not HasAnyEffect) then
            task.delay(0.35, function()
                if not Library or not Library.BackgroundEffects then
                    return
                end

                local CurrentEffects = Library.BackgroundEffects
                if CurrentEffects.IsSnowing then
                    return
                end

                CurrentEffects.Background.Visible = false

                for _, Child in CurrentEffects.SnowHolder:GetChildren() do
                    if Child:IsA("ImageLabel") then
                        Child:Destroy()
                    end
                end
            end)
        end
    end

    Library.SetBackgroundBlurEnabled = function(Self, Bool)
        Library.BackgroundBlurEnabled = Bool and true or false
        Library:SetBackgroundEffectsVisible(Library.WindowOpenState, true)
    end

    Library.SetBackgroundSnowEnabled = function(Self, Bool)
        Library.BackgroundSnowEnabled = Bool and true or false
        Library:SetBackgroundEffectsVisible(Library.WindowOpenState, true)
    end

    Library.Round = function(Self, Number, Float)
        local Multiplier = 1 / (Float or 1)
        return math.floor(Number * Multiplier) / Multiplier
    end

    Library.RegisterLayout = function(Self, Id, Data)
        if type(Id) ~= "string" or Id == "" or type(Data) ~= "table" or not Data.Instance then
            return
        end

        Library.LayoutRegistry[Id] = Data
        return Data
    end

    Library.GetLayoutConfig = function(Self)
        local Layout = {}

        for Id, Data in Library.LayoutRegistry do
            local Instance = Data and Data.Instance
            if not Instance or not Instance.Parent then
                continue
            end

            local Entry = {}
            local Position = Instance.Position

            if Data.SavePosition ~= false then
                Entry.Position = {
                    X = math.floor((tonumber(Position.X.Offset) or 0) + 0.5),
                    Y = math.floor((tonumber(Position.Y.Offset) or 0) + 0.5)
                }
            end

            if Data.SaveSize == true then
                local Size = Instance.Size
                Entry.Size = {
                    X = math.floor((tonumber(Size.X.Offset) or 0) + 0.5),
                    Y = math.floor((tonumber(Size.Y.Offset) or 0) + 0.5)
                }
            end

            if next(Entry) ~= nil then
                Layout[Id] = Entry
            end
        end

        return Layout
    end

    Library.ApplyLayoutConfig = function(Self, Layout)
        if type(Layout) ~= "table" then
            return
        end

        for Id, State in Layout do
            local Data = Library.LayoutRegistry[Id]
            local Instance = Data and Data.Instance
            if not Instance or not Instance.Parent or type(State) ~= "table" then
                continue
            end

            local ParentSize = Instance.Parent.AbsoluteSize
            local MinimumSize = Data.MinimumSize or Vector2.new(0, 0)
            local MaximumSize = Data.MaximumSize

            if Data.SaveSize == true and type(State.Size) == "table" then
                local MaxWidth = math.max(ParentSize.X, MinimumSize.X)
                local MaxHeight = math.max(ParentSize.Y, MinimumSize.Y)

                if typeof(MaximumSize) == "Vector2" then
                    MaxWidth = math.min(MaxWidth, MaximumSize.X)
                    MaxHeight = math.min(MaxHeight, MaximumSize.Y)
                end

                local Width = math.clamp(
                    tonumber(State.Size.X) or Instance.AbsoluteSize.X,
                    math.min(MinimumSize.X, MaxWidth),
                    MaxWidth
                )
                local Height = math.clamp(
                    tonumber(State.Size.Y) or Instance.AbsoluteSize.Y,
                    math.min(MinimumSize.Y, MaxHeight),
                    MaxHeight
                )

                Instance.Size = UDim2.fromOffset(
                    math.floor(Width + 0.5),
                    math.floor(Height + 0.5)
                )
            end

            if Data.SavePosition ~= false and type(State.Position) == "table" then
                local CurrentSize = Instance.AbsoluteSize
                local Width = CurrentSize.X > 0 and CurrentSize.X or (tonumber(Instance.Size.X.Offset) or 0)
                local Height = CurrentSize.Y > 0 and CurrentSize.Y or (tonumber(Instance.Size.Y.Offset) or 0)
                local X = tonumber(State.Position.X) or Instance.Position.X.Offset
                local Y = tonumber(State.Position.Y) or Instance.Position.Y.Offset

                Instance.AnchorPoint = Vector2.new(0, 0)
                Instance.Position = UDim2.fromOffset(
                    math.clamp(math.floor(X + 0.5), 0, math.max(ParentSize.X - Width, 0)),
                    math.clamp(math.floor(Y + 0.5), 0, math.max(ParentSize.Y - Height, 0))
                )
            end
        end
    end

    Library.GetConfig = function(Self)
        local Config = {}

        local Success, Result = Library:SafeCall(function()
            for Index, Value in Library.Flags do
                if type(Value) == "table" and Value.Key then
                    Config[Index] = { Key = tostring(Value.Key), Mode = Value.Mode, Toggled = Value.Toggled }
                elseif type(Value) == "table" and Value.Color then
                    Config[Index] = { Color = "#" .. Value.HexValue, Alpha = Value.Alpha }
                else
                    Config[Index] = Value
                end
            end
        end)

        if not Success then
            warn("Failed to get config:\n" .. Result)
            return
        end

        return HttpService:JSONEncode({
            Flags = Config,
            Layout = Library:GetLayoutConfig()
        })
    end

    Library.LoadConfig = function(Self, Config)
        local Decoded = HttpService:JSONDecode(Config)
        local FlagData = type(Decoded) == "table" and Decoded.Flags or Decoded
        local LayoutData = type(Decoded) == "table" and Decoded.Layout

        local Success, Result = Library:SafeCall(function()
            for Index, Value in FlagData do
                local SetFunction = Library.SetFlags[Index]

                if not SetFunction then
                    continue
                end

                if type(Value) == "table" and Value.Key then
                    SetFunction(Value)
                elseif type(Value) == "table" and Value.Color then
                    SetFunction(Value.Color, Value.Alpha)
                else
                    SetFunction(Value)
                end
            end

            for Index, Value in FlagData do
                if type(Value) ~= "table" or not Value.Key then
                    continue
                end

                local SetFunction = Library.SetFlags[Index]
                if not SetFunction then
                    continue
                end

                SetFunction(Value)
            end
        end)

        if Success and type(LayoutData) == "table" then
            task.defer(function()
                task.wait()
                Library:ApplyLayoutConfig(LayoutData)
            end)
        end

        return Success, Result
    end

    Library.GetConfigsList = function(Self, Element)
        local List = {}
        local ReturnList = {}

        List = listfiles(Library.Directory .. Library.Folders.Configs)

        for Index = 1, #List do
            local File = List[Index]

            if File:sub(-5) == ".json" then
                local Position = File:find(".json", 1, true)
                local StartPosition = Position

                local Character = File:sub(Position, Position)
                while Character ~= "/" and Character ~= "\\" and Character ~= "" do
                    Position = Position - 1
                    Character = File:sub(Position, Position)
                end

                if Character == "/" or Character == "\\" then
                    table.insert(ReturnList, File:sub(Position + 1, StartPosition - 1))
                end
            end
        end

        Element:Refresh(ReturnList)
    end

    Library.AddToTheme = function(Self, Properties)
        local Object = Self.Instance

        local ThemeData = {
            Item = Object,
            Properties = Properties,
        }

        for Property, Value in ThemeData.Properties do
            if type(Value) == "string" then
                if not Library.Theme[Value] then
                    Object[Property] = Value
                end

                Object[Property] = Library.Theme[Value]
            else
                Object[Property] = Value()
            end
        end

        table.insert(Library.ThemingStuff, ThemeData)
        Library.ThemeMap[Object] = ThemeData
        return Self
    end

    Library.ChangeItemTheme = function(Self, Properties)
        local Object = Self.Instance

        if not Library.ThemingStuff[Object] then
            return
        end

        Library.ThemingStuff[Object].Properties = Properties
        Library.ThemingStuff[Object] = Library.ThemeMap[Object]
    end

    Library.ChangeTheme = function(Self, Theme, Color)
        Library.Theme[Theme] = Color

        for _, Item in Library.ThemingStuff do
            for Property, Value in Item.Properties do
                if type(Value) == "string" and Value == Theme then
                    Item.Item[Property] = Color
                elseif type(Value) == "function" then
                    Item.Item[Property] = Value()
                end
            end
        end
    end

    Library.OnHover = function(Self, OnHoverEnter, OnHoverLeave)
        local Object = Self.Instance

        if not Object then
            return
        end

        Library:Connect(Object.MouseEnter, OnHoverEnter)
        Library:Connect(Object.MouseLeave, OnHoverLeave)
    end

    Library.GlobalUpdateOpenFrames = function(Self)
        local StaleEntries = {}

        for Key, Item in Library.OpenFrames do
            if not Item then
                table.insert(StaleEntries, Key)
                continue
            end

            local IsOpen = Item.IsOpen
            local AttachedButton = Item.AttachedButton
            local Frame = Item.Frame

            local CanUpdateNow = Item.CanUpdateNow

            if not IsOpen then
                table.insert(StaleEntries, Key)
                continue
            end

            if not CanUpdateNow then
                continue
            end

            if not AttachedButton or not AttachedButton.Parent or not Frame or not Frame.Parent then
                table.insert(StaleEntries, Key)
                continue
            end

            if CanUpdateNow and IsOpen then
                local ParentSize = Frame.Parent.AbsoluteSize
                local FrameSize = Frame.AbsoluteSize
                local X = AttachedButton.AbsolutePosition.X
                local Y = AttachedButton.AbsolutePosition.Y + AttachedButton.AbsoluteSize.Y + 10 + GuiInset

                if ParentSize.X > 0 and FrameSize.X > 0 then
                    X = math.clamp(X, 0, math.max(ParentSize.X - FrameSize.X, 0))
                end

                if ParentSize.Y > 0 and FrameSize.Y > 0 then
                    Y = math.clamp(Y, 0, math.max(ParentSize.Y - FrameSize.Y, 0))
                end

                Frame.Position = UDim2.fromOffset(X, Y)
            end
        end

        for _, Key in StaleEntries do
            Library.OpenFrames[Key] = nil
        end
    end

    Library.Holder = Library:Create("ScreenGui", {
        Parent = gethui(),
        Name = "\0",
        ZIndexBehavior = Enum.ZIndexBehavior.Global,
        IgnoreGuiInset = true,
        ResetOnSpawn = false
    })

    Library.InputBlocker = Library:Create("TextButton", {
        Parent = Library.Holder.Instance,
        Name = "\0",
        Visible = false,
        Modal = true,
        AutoButtonColor = false,
        Active = true,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 0
    })

    Library.MouseCursor = Library:Create("ImageLabel", {
        Parent = Library.Holder.Instance,
        Name = "\0",
        Visible = false,
        BackgroundTransparency = 1,
        Image = "http://www.roblox.com/asset/?id=5545698398",
        Size = UDim2.new(0, 36, 0, 36),
        ZIndex = 10000
    })

    Library.UnusedHolder = Library:Create("ScreenGui", {
        Parent = gethui(),
        Name = "\0",
        Enabled = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Global,
        ResetOnSpawn = false
    })

    Library:SetupBackgroundEffects()
    Library:SetBackgroundEffectsVisible(false, true)

    Library.NotifHolder = Library:Create("Frame", {
        Name = "\0",
        Parent = Library.Holder.Instance,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 10 + GuiInset),
        Size = UDim2.new(0, 0, 1, 0),
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.X
    })

    Library:Create("UIListLayout", {
        Name = "\0",
        Parent = Library.NotifHolder.Instance,
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        Padding = UDim.new(0, 6)
    })

    Library:Create("UIPadding", {
        Name = "\0",
        Parent = Library.NotifHolder.Instance,
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8)
    })

    Library:Connect(RunService.RenderStepped, function()
        local MouseCursor = Library.MouseCursor
        if not (MouseCursor and MouseCursor.Instance and Library.WindowOpenState) then
            return
        end

        local MouseLocation = UserInputService:GetMouseLocation()
        MouseCursor.Instance.Position = UDim2.new(0, MouseLocation.X - 18, 0, MouseLocation.Y - 18)
    end)

    do
        Library.CreateColorpicker = function(Self, Data)
            local Colorpicker = {
                Hue = 0,
                Saturation = 0,
                Value = 0,

                Alpha = 0,

                Color = Color3.fromRGB(255, 255, 255),
                HexValue = "#FFFFFF",

                Flag = Data.Flag,
                IsOpen = false,

                Items = {}
            }

            local Items = {}
            do
                Items["ColorpickerButton"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Data.Parent.Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Size = UDim2.new(0, 22, 0, 12),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(158, 255, 252)
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ColorpickerButton"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["ColorpickerButton"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["ColorpickerWindow"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Library.UnusedHolder.Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 1056, 0, 203),
                    Size = UDim2.new(0, 230, 0, 205),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ColorpickerWindow"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ColorpickerWindow"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["Shadow"] = Library:Create("ImageLabel", {
                    Name = "\0",
                    Parent = Items["ColorpickerWindow"].Instance,
                    ImageColor3 = Color3.fromRGB(103, 164, 255),
                    ScaleType = Enum.ScaleType.Slice,
                    ImageTransparency = 0.699999988079071,
                    Size = UDim2.new(1, 25, 1, 25),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Image = "http://www.roblox.com/asset/?id=18245826428",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    ZIndex = -1,
                    BorderSizePixel = 0,
                    SliceCenter = Rect.new(Vector2.new(21, 21), Vector2.new(79, 79))
                })

                Items["Palette"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["ColorpickerWindow"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 10, 0, 12),
                    Size = UDim2.new(1, -46, 1, -48),
                    BorderSizePixel = 0,
                })

                Items["Saturation"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Palette"].Instance,
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0
                })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["Saturation"].Instance,
                    Transparency = NumberSequence.new {
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(1, 0)
                    }
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Palette"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Items["Value"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Palette"].Instance,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["Value"].Instance,
                    Rotation = 90,
                    Transparency = NumberSequence.new {
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(1, 0)
                    }
                })

                Items["PaletteDragger"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Palette"].Instance,
                    Size = UDim2.new(0, 1, 0, 1),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["PaletteDragger"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ColorpickerWindow"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Hue"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["ColorpickerWindow"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    AnchorPoint = Vector2.new(1, 0),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    Position = UDim2.new(1, -10, 0, 12),
                    Size = UDim2.new(0, 15, 1, -20),
                    BorderSizePixel = 0
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Hue"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["Hue"].Instance,
                    Rotation = 90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
                        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
                    }
                })

                Items["HueDragger"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Hue"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["HueDragger"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Items["Alpha"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    Parent = Items["ColorpickerWindow"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 10, 1, -10),
                    Size = UDim2.new(1, -46, 0, 15),
                    BorderSizePixel = 0
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Alpha"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Items["AlphaColor"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Alpha"].Instance,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(158, 255, 252)
                })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["AlphaColor"].Instance,
                    Transparency = NumberSequence.new {
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(1, 0)
                    }
                })

                Items["AlphaDragger"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Alpha"].Instance,
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    Size = UDim2.new(0, 1, 1, 0),
                    BorderSizePixel = 0
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["AlphaDragger"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Items["CopyPasteWindow"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Library.UnusedHolder.Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 1056, 0, 203),
                    Size = UDim2.new(0, 96, 0, 44),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"],
                    Visible = false
                }):AddToTheme({ BackgroundColor3 = "Background" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CopyPasteWindow"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CopyPasteWindow"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["CopyButton"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["CopyPasteWindow"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "Copy",
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 4, 0, 4),
                    Size = UDim2.new(1, -8, 0, 16),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({
                    BackgroundColor3 = "Element",
                    TextColor3 = "Text"
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CopyButton"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CopyButton"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["CopyButton"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["PasteButton"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["CopyPasteWindow"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "Paste",
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 4, 0, 24),
                    Size = UDim2.new(1, -8, 0, 16),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({
                    BackgroundColor3 = "Element",
                    TextColor3 = "Text"
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["PasteButton"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["PasteButton"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["PasteButton"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Colorpicker.Items = Items
            end

            function Colorpicker:SetVisibility(Bool)
                Items["ColorpickerButton"].Instance.Visible = Bool
            end

            function Colorpicker:Update(IsFromAlpha)
                local Hue, Saturation, Value = Colorpicker.Hue, Colorpicker.Saturation, Colorpicker.Value
                Colorpicker.Color = Color3.fromHSV(Hue, Saturation, Value)
                Colorpicker.HexValue = Colorpicker.Color:ToHex()

                Items["ColorpickerButton"]:Tween({ BackgroundColor3 = Colorpicker.Color })
                Items["Palette"]:Tween({ BackgroundColor3 = Color3.fromHSV(Hue, 1, 1) })

                Flags[Colorpicker.Flag] = {
                    Alpha = Colorpicker.Alpha,
                    Color = Colorpicker.Color,
                    HexValue = Colorpicker.HexValue,
                    Transparency = 1 - Colorpicker.Alpha
                }

                if not IsFromAlpha then
                    Items["AlphaColor"]:Tween({ BackgroundColor3 = Colorpicker.Color })
                end

                if Data.Callback then
                    Library:SafeCall(Data.Callback, Colorpicker.Color, Colorpicker.Alpha)
                end
            end

            local Debounce = false
            local RenderStepped
            local ColorpickerWindow = Items["ColorpickerWindow"].Instance
            local ColorpickerButton = Items["ColorpickerButton"].Instance
            local CopyPasteDebounce = false
            local CopyPasteWindow = Items["CopyPasteWindow"].Instance
            local CopyToClipboard = setclipboard or toclipboard

            Colorpicker.AttachedButton = ColorpickerButton
            Colorpicker.CanUpdateNow = false
            Colorpicker.Frame = ColorpickerWindow

            local function ResolveAttachedFramePosition(Frame)
                local Parent = Frame and Frame.Parent
                local ParentSize = Parent and Parent.AbsoluteSize or Vector2.new(0, 0)
                local FrameSize = Frame and Frame.AbsoluteSize or Vector2.new(0, 0)
                local X = ColorpickerButton.AbsolutePosition.X
                local Y = ColorpickerButton.AbsolutePosition.Y + ColorpickerButton.AbsoluteSize.Y + 10 + GuiInset

                if ParentSize.X > 0 and FrameSize.X > 0 then
                    X = math.clamp(X, 0, math.max(ParentSize.X - FrameSize.X, 0))
                end

                if ParentSize.Y > 0 and FrameSize.Y > 0 then
                    Y = math.clamp(Y, 0, math.max(ParentSize.Y - FrameSize.Y, 0))
                end

                return UDim2.fromOffset(X, Y)
            end

            local CopyPasteMenu = {
                IsOpen = false,
                AttachedButton = ColorpickerButton,
                CanUpdateNow = false,
                Frame = CopyPasteWindow
            }

            function CopyPasteMenu:SetOpen(Bool)
                if CopyPasteDebounce then
                    return
                end

                CopyPasteMenu.IsOpen = Bool and true or false
                CopyPasteDebounce = true

                if CopyPasteMenu.IsOpen then
                    if Colorpicker.IsOpen then
                        Colorpicker:SetOpen(false)
                    end

                    CopyPasteWindow.Parent = Library.Holder.Instance
                    CopyPasteWindow.Position = ResolveAttachedFramePosition(CopyPasteWindow)
                    CopyPasteWindow.Visible = true

                    Items["CopyPasteWindow"]:Tween({
                        Position = ResolveAttachedFramePosition(CopyPasteWindow)
                    })

                    Items["CopyPasteWindow"]:FadeDescendants(true, function()
                        CopyPasteMenu.CanUpdateNow = true
                        CopyPasteDebounce = false
                    end)

                    for _, Value in Library.OpenFrames do
                        if not Data.Section.IsSettings and Value ~= CopyPasteMenu then
                            Value:SetOpen(false)
                        end
                    end

                    Library.OpenFrames[CopyPasteMenu] = CopyPasteMenu
                else
                    Items["CopyPasteWindow"]:Tween({
                        Position = ResolveAttachedFramePosition(CopyPasteWindow)
                    })

                    Items["CopyPasteWindow"]:FadeDescendants(false, function()
                        CopyPasteWindow.Parent = Library.UnusedHolder.Instance
                        CopyPasteMenu.CanUpdateNow = false
                        CopyPasteDebounce = false
                    end)

                    if Library.OpenFrames[CopyPasteMenu] then
                        Library.OpenFrames[CopyPasteMenu] = nil
                    end
                end

                local Descendants = CopyPasteWindow:GetDescendants()
                table.insert(Descendants, CopyPasteWindow)

                for _, Value in Descendants do
                    if Value.ClassName:find("UI") then
                        continue
                    end

                    Value.ZIndex = CopyPasteMenu.IsOpen and 4 or 1
                end
            end

            function Colorpicker:SetOpen(Bool)
                if Debounce then
                    return
                end

                Colorpicker.IsOpen = Bool

                Debounce = true

                if Colorpicker.IsOpen then
                    ColorpickerWindow.Parent = Library.Holder.Instance
                    ColorpickerWindow.Position = ResolveAttachedFramePosition(ColorpickerWindow)
                    ColorpickerWindow.Visible = true
                    Items["ColorpickerWindow"]:Tween({
                        Position = ResolveAttachedFramePosition(ColorpickerWindow)
                    })

                    Items["ColorpickerWindow"]:FadeDescendants(true, function()
                        Colorpicker.CanUpdateNow = true
                        Debounce = false
                    end)

                    for Index, Value in Library.OpenFrames do
                        if not Data.Section.IsSettings then
                            Value:SetOpen(false)
                        end
                    end

                    Library.OpenFrames[Colorpicker] = Colorpicker
                else
                    Items["ColorpickerWindow"]:Tween({
                        Position = ResolveAttachedFramePosition(ColorpickerWindow)
                    })
                    Items["ColorpickerWindow"]:FadeDescendants(false, function()
                        ColorpickerWindow.Parent = Library.UnusedHolder.Instance
                        Colorpicker.CanUpdateNow = false
                        Debounce = false
                    end)

                    if Library.OpenFrames[Colorpicker] then
                        Library.OpenFrames[Colorpicker] = nil
                    end

                    if RenderStepped then
                        RenderStepped:Disconnect()
                        RenderStepped = nil
                    end
                end

                local Descendants = ColorpickerWindow:GetDescendants()
                table.insert(Descendants, ColorpickerWindow)

                for Index, Value in Descendants do
                    if Value.ClassName:find("UI") then
                        continue
                    end

                    Value.ZIndex = Colorpicker.IsOpen and 4 or 1
                end

                Items["PaletteDragger"].Instance.ZIndex = 5
                Items["HueDragger"].Instance.ZIndex = 5
                Items["AlphaDragger"].Instance.ZIndex = 5
                Items["Shadow"].Instance.ZIndex = 3
            end

            local SlidingPalette = false
            local PaletteChanged

            function Colorpicker:SlidePalette(Input)
                if not Input or not SlidingPalette then
                    return
                end

                local ValueX = math.clamp(
                    1 -
                    (Input.Position.X - Items["Palette"].Instance.AbsolutePosition.X) /
                    Items["Palette"].Instance.AbsoluteSize.X, 0, 1)
                local ValueY = math.clamp(
                    1 -
                    (Input.Position.Y - Items["Palette"].Instance.AbsolutePosition.Y) /
                    Items["Palette"].Instance.AbsoluteSize.Y, 0, 1)

                Colorpicker.Saturation = ValueX
                Colorpicker.Value = ValueY

                local SlideX = math.clamp(
                    (Input.Position.X - Items["Palette"].Instance.AbsolutePosition.X) /
                    Items["Palette"].Instance.AbsoluteSize.X, 0, 1)
                local SlideY = math.clamp(
                    (Input.Position.Y - Items["Palette"].Instance.AbsolutePosition.Y) /
                    Items["Palette"].Instance.AbsoluteSize.Y, 0, 1)

                Items["PaletteDragger"]:Tween({ Position = UDim2.new(SlideX, 0, SlideY, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Colorpicker:Update()
            end

            local SlidingHue = false
            local HueChanged

            function Colorpicker:SlideHue(Input)
                if not Input or not SlidingHue then
                    return
                end

                local ValueY = math.clamp(
                    (Input.Position.Y - Items["Hue"].Instance.AbsolutePosition.Y) / Items["Hue"].Instance.AbsoluteSize.Y,
                    0,
                    1)

                Colorpicker.Hue = ValueY

                local SlideY = math.clamp(
                    (Input.Position.Y - Items["Hue"].Instance.AbsolutePosition.Y) / Items["Hue"].Instance.AbsoluteSize.Y,
                    0,
                    1)

                Items["HueDragger"]:Tween({ Position = UDim2.new(0, 0, SlideY, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Colorpicker:Update()
            end

            local SlidingAlpha = false
            local AlphaChanged

            function Colorpicker:SlideAlpha(Input)
                if not Input or not SlidingAlpha then
                    return
                end

                local ValueX = math.clamp(
                    (Input.Position.X - Items["Alpha"].Instance.AbsolutePosition.X) /
                    Items["Alpha"].Instance.AbsoluteSize.X,
                    0, 1)

                Colorpicker.Alpha = ValueX

                local SlideX = math.clamp(
                    (Input.Position.X - Items["Alpha"].Instance.AbsolutePosition.X) /
                    Items["Alpha"].Instance.AbsoluteSize.X,
                    0, 1)

                Items["AlphaDragger"]:Tween({ Position = UDim2.new(SlideX, 0, 0, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Colorpicker:Update(true)
            end

            function Colorpicker:Set(Color, Alpha)
                if type(Color) == "table" then
                    Color = Color3.fromRGB(Color[1], Color[2], Color[3])
                elseif type(Color) == "string" then
                    Color = Color3.fromHex(Color)
                else
                    Color = Color -- lul
                end

                Colorpicker.Hue, Colorpicker.Saturation, Colorpicker.Value = Color:ToHSV()
                Colorpicker.Alpha = Alpha or 0

                local PaletteValueX = math.clamp(1 - Colorpicker.Saturation, 0, 1)
                local PaletteValueY = math.clamp(1 - Colorpicker.Value, 0, 1)

                local AlphaPositionX = math.clamp(Colorpicker.Alpha, 0, 1)

                local HuePositionY = math.clamp(Colorpicker.Hue, 0, 1)

                Items["PaletteDragger"]:Tween({ Position = UDim2.new(PaletteValueX, 0, PaletteValueY, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Items["HueDragger"]:Tween({ Position = UDim2.new(0, 0, HuePositionY, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Items["AlphaDragger"]:Tween({ Position = UDim2.new(AlphaPositionX, 0, 0, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Colorpicker:Update()
            end

            Items["ColorpickerButton"]:Connect("MouseButton1Down", function()
                if CopyPasteMenu.IsOpen then
                    CopyPasteMenu:SetOpen(false)
                end

                Colorpicker:SetOpen(not Colorpicker.IsOpen)
            end)

            Items["ColorpickerButton"]:Connect("MouseButton2Down", function()
                CopyPasteMenu:SetOpen(not CopyPasteMenu.IsOpen)
            end)

            Items["CopyButton"]:Connect("MouseButton1Down", function()
                Library.CopiedColor = Colorpicker.Color

                if CopyToClipboard then
                    pcall(CopyToClipboard, "#" .. Colorpicker.HexValue)
                end

                CopyPasteMenu:SetOpen(false)
            end)

            Items["PasteButton"]:Connect("MouseButton1Down", function()
                if Library.CopiedColor then
                    Colorpicker:Set(Library.CopiedColor, Colorpicker.Alpha)
                end

                CopyPasteMenu:SetOpen(false)
            end)

            Items["Palette"]:Connect("InputBegan", function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    SlidingPalette = true

                    Colorpicker:SlidePalette(Input)

                    if PaletteChanged then
                        return
                    end

                    PaletteChanged = Input.Changed:Connect(function()
                        if Input.UserInputState == Enum.UserInputState.End then
                            SlidingPalette = false

                            PaletteChanged:Disconnect()
                            PaletteChanged = nil
                        end
                    end)
                end
            end)

            Items["Hue"]:Connect("InputBegan", function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    SlidingHue = true

                    Colorpicker:SlideHue(Input)

                    if HueChanged then
                        return
                    end

                    HueChanged = Input.Changed:Connect(function()
                        if Input.UserInputState == Enum.UserInputState.End then
                            SlidingHue = false

                            HueChanged:Disconnect()
                            HueChanged = nil
                        end
                    end)
                end
            end)

            Items["Alpha"]:Connect("InputBegan", function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    SlidingAlpha = true

                    Colorpicker:SlideAlpha(Input)

                    if AlphaChanged then
                        return
                    end

                    AlphaChanged = Input.Changed:Connect(function()
                        if Input.UserInputState == Enum.UserInputState.End then
                            SlidingAlpha = false

                            AlphaChanged:Disconnect()
                            AlphaChanged = nil
                        end
                    end)
                end
            end)

            Library:Connect(UserInputService.InputChanged, function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
                    if SlidingPalette then
                        Colorpicker:SlidePalette(Input)
                    end

                    if SlidingHue then
                        Colorpicker:SlideHue(Input)
                    end

                    if SlidingAlpha then
                        Colorpicker:SlideAlpha(Input)
                    end
                end
            end)

            Library:Connect(UserInputService.InputBegan, function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    if not Colorpicker.IsOpen then
                        if CopyPasteMenu.IsOpen and not Items["CopyPasteWindow"]:IsMouseOverFrame() then
                            CopyPasteMenu:SetOpen(false)
                        end

                        return
                    end

                    if Items["ColorpickerWindow"]:IsMouseOverFrame() then
                        return
                    end

                    Colorpicker:SetOpen(false)
                end
            end)

            if Data.Default then
                Colorpicker:Set(Data.Default, Data.Alpha)
            end

            SetFlags[Colorpicker.Flag] = function(Value, Alpha)
                Colorpicker:Set(Value, Alpha)
            end

            return Colorpicker, Items
        end

        Library.CreateKeybind = function(Self, Data)
            local Keybind = {
                Flag = Data.Flag,
                IsOpen = false,

                Key = "",
                Mode = "",
                Value = "",

                Toggled = false,
                Picking = false,

                Items = {}
            }

            local Items = {}
            do
                Items["KeyButton"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Data.Parent.Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "[...]",
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["KeybindWindow"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Library.UnusedHolder.Instance,
                    Visible = false,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Position = UDim2.new(0.7021276354789734, 0, 0.4859813153743744, 0),
                    Size = UDim2.new(0, 200, 0, 82),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["KeybindWindow"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["KeybindWindow"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["KeybindWindow"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Keybind.Items = Items
            end

            local KeybindObject

            if Library.KeyList then
                KeybindObject = Library.KeyList:Add("", "", "")
            end

            local Update = function()
                if KeybindObject then
                    KeybindObject:SetStatus(Keybind.Toggled)
                    KeybindObject:Set(Keybind.Value, Data.Name, Keybind.Mode)
                end
            end

            local Debounce = false
            local RenderStepped
            local KeybindWindow = Items["KeybindWindow"].Instance
            local KeyButton = Items["KeyButton"].Instance

            Keybind.AttachedButton = KeyButton
            Keybind.CanUpdateNow = false
            Keybind.Frame = KeybindWindow

            local ModeDropdown = Library:Dropdown({
                Name = "Mode",
                Flag = Data.Flag .. "Mode",
                Parent = Items["KeybindWindow"],
                Items = { "Toggle", "Hold", "Always" },
                Default = "Toggle",
                Callback = function(Value)
                    Keybind.Mode = Value
                    if Value == "Always" then
                        Keybind.Toggled = true
                    end

                    Flags[Keybind.Flag] = {
                        Mode = Keybind.Mode,
                        Key = Keybind.Key,
                        Toggled = Keybind.Toggled
                    }

                    if Data.Callback then
                        Library:SafeCall(Data.Callback, Keybind.Toggled)
                    end

                    Update()
                end
            })

            local ShowInKeybindsList = Library:Toggle({
                Name = "Show in keybinds list",
                Flag = Data.Flag .. "ShowInKeybindsList",
                Parent = Items["KeybindWindow"],
                Default = true,
                Callback = function(Value)
                    if KeybindObject then
                        KeybindObject:SetVis(Value)
                        Update()
                    end
                end
            })

            ShowInKeybindsList.Items.Toggle.Instance.Position = UDim2.new(0, 8, 1, -8)
            ShowInKeybindsList.Items.Toggle.Instance.Size = UDim2.new(1, -16, 0, 12)
            ShowInKeybindsList.Items.Toggle.Instance.AnchorPoint = Vector2.new(0, 1)
            ShowInKeybindsList.Items.Indicator.Instance.Position = UDim2.new(0, 0, 0.5, 0)
            ShowInKeybindsList.Items.Text.Instance.Position = UDim2.new(0, 15, 0.5, -1)

            ModeDropdown.Items.Dropdown.Instance.Position = UDim2.new(0, 8, 0, 8)
            ModeDropdown.Items.Dropdown.Instance.Size = UDim2.new(1, -16, 0, 40)

            function Keybind:SetOpen(Bool)
                if Debounce then
                    return
                end

                Keybind.IsOpen = Bool

                Debounce = true

                if Keybind.IsOpen then
                    KeybindWindow.Position = UDim2.new(0, KeyButton.AbsolutePosition.X, 0,
                        KeyButton.AbsolutePosition.Y + KeyButton.AbsoluteSize.Y + GuiInset)

                    KeybindWindow.Parent = Library.Holder.Instance
                    KeybindWindow.Visible = true
                    Items["KeybindWindow"]:Tween({
                        Position = UDim2.new(0, KeyButton.AbsolutePosition.X, 0,
                            KeyButton.AbsolutePosition.Y + KeyButton.AbsoluteSize.Y + 10 + GuiInset)
                    })

                    Items["KeybindWindow"]:FadeDescendants(true, function()
                        Debounce = false
                        Keybind.CanUpdateNow = true
                    end)

                    for Index, Value in Library.OpenFrames do
                        if not Data.Section.IsSettings then
                            Value:SetOpen(false)
                        end
                    end

                    Library.OpenFrames[Keybind] = Keybind
                else
                    Items["KeybindWindow"]:Tween({
                        Position = UDim2.new(0, KeyButton.AbsolutePosition.X, 0,
                            KeyButton.AbsolutePosition.Y + KeyButton.AbsoluteSize.Y - 10 + GuiInset)
                    })
                    Items["KeybindWindow"]:FadeDescendants(false, function()
                        Items["KeybindWindow"].Instance.Parent = Library.UnusedHolder.Instance
                        Debounce = false
                        Keybind.CanUpdateNow = false
                    end)

                    if Library.OpenFrames[Keybind] then
                        Library.OpenFrames[Keybind] = nil
                    end

                    if RenderStepped then
                        RenderStepped:Disconnect()
                        RenderStepped = nil
                    end
                end

                local Descendants = KeybindWindow:GetDescendants()
                table.insert(Descendants, KeybindWindow)

                for Index, Value in Descendants do
                    if Value.ClassName:find("UI") then
                        continue
                    end

                    Value.ZIndex = Keybind.IsOpen and 4 or 1
                end
            end

            function Keybind:SetMode(Mode)
                ModeDropdown:Set(Mode)
                if Mode == "Always" then
                    Keybind.Toggled = true
                end

                Flags[Keybind.Flag] = {
                    Mode = Keybind.Mode,
                    Key = Keybind.Key,
                    Toggled = Keybind.Toggled
                }

                if Data.Callback then
                    Library:SafeCall(Data.Callback, Keybind.Toggled)
                end

                Update()
            end

            function Keybind:Press(Bool)
                if Keybind.Mode == "Toggle" then
                    Keybind.Toggled = not Keybind.Toggled
                elseif Keybind.Mode == "Hold" then
                    Keybind.Toggled = Bool
                elseif Keybind.Mode == "Always" then
                    Keybind.Toggled = true
                end

                Flags[Keybind.Flag] = {
                    Mode = Keybind.Mode,
                    Key = Keybind.Key,
                    Toggled = Keybind.Toggled
                }

                if Data.Callback then
                    Library:SafeCall(Data.Callback, Keybind.Toggled)
                end

                Update()
            end

            function Keybind:Set(Key)
                if string.find(tostring(Key), "Enum") then
                    Keybind.Key = tostring(Key)

                    Key = Key.Name == "Backspace" and "None" or Key.Name

                    local KeyString = Keys[Keybind.Key] or string.gsub(Key, "Enum.", "") or "None"
                    local TextToDisplay = string.gsub(string.gsub(KeyString, "KeyCode.", ""), "UserInputType.", "") or
                        "None"

                    Keybind.Value = TextToDisplay
                    Items["KeyButton"].Instance.Text = "[" .. TextToDisplay .. "]"

                    Flags[Keybind.Flag] = {
                        Mode = Keybind.Mode,
                        Key = Keybind.Key,
                        Toggled = Keybind.Toggled
                    }

                    if Data.Callback then
                        Library:SafeCall(Data.Callback, Keybind.Toggled)
                    end

                    Update()
                elseif type(Key) == "table" then
                    local RealKey = Key.Key == "Backspace" and "None" or Key.Key
                    Keybind.Key = tostring(Key.Key)

                    if Key.Mode then
                        Keybind.Mode = Key.Mode
                        Keybind:SetMode(Key.Mode)
                    else
                        Keybind.Mode = "Toggle"
                        Keybind:SetMode("Toggle")
                    end

                    local KeyString = Keys[Keybind.Key] or string.gsub(tostring(RealKey), "Enum.", "") or RealKey
                    local TextToDisplay = KeyString and
                        string.gsub(string.gsub(KeyString, "KeyCode.", ""), "UserInputType.", "") or "None"

                    TextToDisplay = string.gsub(string.gsub(KeyString, "KeyCode.", ""), "UserInputType.", "")

                    Keybind.Value = TextToDisplay
                    Items["KeyButton"].Instance.Text = "[" .. TextToDisplay .. "]"
                    if Keybind.Mode == "Always" then
                        Keybind.Toggled = true
                    elseif type(Key.Toggled) == "boolean" then
                        Keybind.Toggled = Key.Toggled
                    end

                    Flags[Keybind.Flag] = {
                        Mode = Keybind.Mode,
                        Key = Keybind.Key,
                        Toggled = Keybind.Toggled
                    }

                    if Data.Callback then
                        Library:SafeCall(Data.Callback, Keybind.Toggled)
                    end

                    Update()
                elseif table.find({ "Toggle", "Hold", "Always" }, Key) then
                    Keybind.Mode = Key
                    Keybind:SetMode(Key)

                    if Data.Callback then
                        Library:SafeCall(Data.Callback, Keybind.Toggled)
                    end

                    Update()
                end

                Keybind.Picking = false
            end

            Items["KeyButton"]:Connect("MouseButton1Click", function()
                if Keybind.Disabled then
                    return
                end

                Keybind.Picking = true

                Items["KeyButton"].Instance.Text = "press a key"

                local InputBegan
                InputBegan = UserInputService.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        Keybind:Set(Input.KeyCode)
                    else
                        Keybind:Set(Input.UserInputType)
                    end

                    InputBegan:Disconnect()
                    InputBegan = nil
                end)
            end)

            Library:Connect(UserInputService.InputBegan, function(Input, GPE)
                if Keybind.Value == "None" then
                    return
                end

                if not GPE then
                    if tostring(Input.KeyCode) == Keybind.Key then
                        if Keybind.Mode == "Toggle" then
                            Keybind:Press()
                        elseif Keybind.Mode == "Hold" then
                            Keybind:Press(true)
                        elseif Keybind.Mode == "Always" then
                            Keybind:Press(true)
                        end
                    elseif tostring(Input.UserInputType) == Keybind.Key then
                        if Keybind.Mode == "Toggle" then
                            Keybind:Press()
                        elseif Keybind.Mode == "Hold" then
                            Keybind:Press(true)
                        elseif Keybind.Mode == "Always" then
                            Keybind:Press(true)
                        end
                    end
                end

                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    if not Keybind.IsOpen then
                        return
                    end

                    if Items["KeybindWindow"]:IsMouseOverFrame() or ModeDropdown.Items.OptionHolder:IsMouseOverFrame() then
                        return
                    end

                    Keybind:SetOpen(false)
                end
            end)

            Library:Connect(UserInputService.InputEnded, function(Input, GPE)
                if GPE then
                    return
                end

                if Keybind.Value == "None" then
                    return
                end

                if tostring(Input.KeyCode) == Keybind.Key then
                    if Keybind.Mode == "Hold" then
                        Keybind:Press(false)
                    elseif Keybind.Mode == "Always" then
                        Keybind:Press(true)
                    end
                elseif tostring(Input.UserInputType) == Keybind.Key then
                    if Keybind.Mode == "Hold" then
                        Keybind:Press(false)
                    elseif Keybind.Mode == "Always" then
                        Keybind:Press(true)
                    end
                end
            end)

            Items["KeyButton"]:Connect("MouseButton2Down", function()
                Keybind:SetOpen(not Keybind.IsOpen)
            end)

            if Data.Default then
                Keybind:Set({
                    Mode = Data.Mode or "Toggle",
                    Key = Data.Default,
                })
            end

            SetFlags[Keybind.Flag] = function(Value)
                Keybind:Set(Value)
            end

            return Keybind, Items
        end

        Library.Watermark = function(Self, Params)
            local Watermark = {}
            local PrefixText = tostring((Params and Params.Name) or "niggahack")
            local WatermarkTick = tick()
            local WatermarkFps = 0
            local WatermarkDisplayedFps = 0
            local WatermarkStatsText = ""
            local DynamicTextProvider = nil
            local DynamicText = PrefixText
            local DynamicTextTick = 0
            local WatermarkLastShimmerTime = tick()
            local WatermarkShimmerPhase = 0

            local Items = {}
            do
                Items["Watermark"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    AnchorPoint = Vector2.new(0.5, 0),
                    Position = UDim2.new(0.5, 0, 0, 42),
                    Size = UDim2.new(0, 0, 0, 25),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["Watermark"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Watermark"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Watermark"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Watermark"].Instance,
                    Position = UDim2.new(0, -8, 0, 1),
                    Size = UDim2.new(1, 16, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = 'Light Border' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Watermark"].Instance,
                    Position = UDim2.new(0, -8, 0, 0),
                    Size = UDim2.new(1, 16, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["AccentGradient"] = Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["AccentLiner"].Instance,
                    Offset = Vector2.new(0, 0),
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0),
                        NumberSequenceKeypoint.new(0.5, 1),
                        NumberSequenceKeypoint.new(1, 0),
                    })
                })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Watermark"].Instance,
                    RichText = true,
                    TextColor3 = Library.Theme["Text"],
                    Text = PrefixText,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Size = UDim2.new(0, 0, 0, 15),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0.5, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Watermark"].Instance,
                    PaddingRight = UDim.new(0, 8),
                    PaddingLeft = UDim.new(0, 8)
                })
            end

            function Watermark:SetVisibility(Bool)
                Items["Watermark"].Instance.Visible = Bool
            end

            function Watermark:Center()
                local AbsPos = Items["Watermark"].Instance.AbsolutePosition
                Items["Watermark"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["Watermark"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Watermark:SetText(Text)
                DynamicTextProvider = nil
                PrefixText = tostring(Text or "")
                DynamicText = PrefixText
                Items["Text"].Instance.Text = PrefixText
            end

            function Watermark:SetDynamicTextProvider(Callback)
                DynamicTextProvider = type(Callback) == "function" and Callback or nil
                DynamicTextTick = 0
                DynamicText = PrefixText
            end

            function Watermark:SetName(Text)
                self:SetText(Text)
            end

            function Watermark:GetBounds()
                local Instance = Items["Watermark"].Instance
                return Instance.AbsolutePosition, Instance.AbsoluteSize
            end

            Library:RegisterLayout("Watermark", {
                Instance = Items["Watermark"].Instance
            })

            Library:Connect(RunService.RenderStepped, function()
                if not Items["Watermark"].Instance.Visible then
                    return
                end

                local CurrentTick = tick()
                WatermarkFps += 1

                if CurrentTick - WatermarkLastShimmerTime >= (1 / 30) then
                    WatermarkShimmerPhase = (WatermarkShimmerPhase + (CurrentTick - WatermarkLastShimmerTime) * (1 / 1.2)) %
                        1
                    WatermarkLastShimmerTime = CurrentTick
                    if DynamicTextProvider and (CurrentTick - DynamicTextTick) >= 0.25 then
                        DynamicTextTick = CurrentTick
                        DynamicText = tostring(DynamicTextProvider(WatermarkDisplayedFps) or "")
                    end
                    local PlainText = DynamicTextProvider and DynamicText or (PrefixText .. WatermarkStatsText)
                    local ShineWidth = 6
                    local ShinePos = WatermarkShimmerPhase * (#PlainText + ShineWidth)
                    local Rich = {}
                    for Index = 1, #PlainText do
                        local Distance = math.abs(Index - ShinePos)
                        local Alpha = math.clamp(1 - (Distance / ShineWidth), 0, 1)
                        local Color = Library.Theme["Text"]:Lerp(Library.Theme["Accent"], Alpha)
                        Rich[#Rich + 1] = string.format(
                            '<font color="rgb(%d,%d,%d)">%s</font>',
                            math.floor(Color.R * 255),
                            math.floor(Color.G * 255),
                            math.floor(Color.B * 255),
                            PlainText:sub(Index, Index)
                        )
                    end

                    Items["AccentGradient"].Instance.Offset = Vector2.new((WatermarkShimmerPhase * 2) - 1, 0)
                    Items["Text"].Instance.Text = table.concat(Rich)
                end

                if CurrentTick - WatermarkTick >= 1 then
                    WatermarkTick = CurrentTick
                    WatermarkDisplayedFps = WatermarkFps
                    if not DynamicTextProvider then
                        WatermarkStatsText = string.format(
                            ' / %s / %sfps',
                            os.date("%a %b %d %X %Y"),
                            WatermarkDisplayedFps
                        )
                    else
                        WatermarkStatsText = ""
                    end
                    WatermarkFps = 0
                end
            end)

            Watermark:Center()

            return Watermark
        end

        Library.KeybindList = function(Self, Params)
            local KeybindList = {}
            Library.KeyList = KeybindList

            local Items = {}
            do
                Items["KeybindList"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 10, 0.5, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.XY,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["KeybindList"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["KeybindList"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["KeybindList"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["KeybindList"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Params.Name,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 15),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["KeybindList"].Instance,
                    PaddingTop = UDim.new(0, 4),
                    PaddingBottom = UDim.new(0, 4),
                    PaddingRight = UDim.new(0, 8),
                    PaddingLeft = UDim.new(0, 8)
                })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["KeybindList"].Instance,
                    Position = UDim2.new(0, -2, 0, 20),
                    Size = UDim2.new(1, 4, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["Content"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["KeybindList"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0, 25),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.XY
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    Padding = UDim.new(0, 2),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["KeybindList"].Instance,
                    PaddingTop = UDim.new(0, 4),
                    PaddingBottom = UDim.new(0, 4),
                    PaddingRight = UDim.new(0, 8),
                    PaddingLeft = UDim.new(0, 8)
                })
            end

            function KeybindList:SetVisibility(Bool)
                Items["KeybindList"].Instance.Visible = Bool
            end

            function KeybindList:Center()
                local AbsPos = Items["KeybindList"].Instance.AbsolutePosition
                Items["KeybindList"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["KeybindList"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function KeybindList:SetText(Text)
                Items["KeybindList"].Instance.Text = Text
            end

            function KeybindList:Add(Key, Name, Mode)
                local CanShowInKeybindsList = true

                local NewKey = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Content"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Key .. " - " .. Name .. " - " .. Mode,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 15),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                function NewKey:Set(Key, Name, Mode)
                    NewKey.Instance.Text = Key .. " - " .. Name .. " - " .. Mode
                end

                function NewKey:SetStatus(Bool)
                    if not CanShowInKeybindsList then
                        Bool = false
                    end

                    NewKey.Instance.Visible = Bool
                end

                function NewKey:SetVis(Bool)
                    CanShowInKeybindsList = Bool
                end

                return NewKey
            end

            KeybindList.Items = Items

            Library:RegisterLayout("KeybindList", {
                Instance = Items["KeybindList"].Instance
            })

            return KeybindList
        end

        Library.Notification = function(Self, Name, Duration, Color)
            local Items = {}
            do
                Items["Notification"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.NotifHolder.Instance,
                    Size = UDim2.new(0, 0, 0, 20),
                    Position = UDim2.new(0, 471, 0, 678),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Notification"].Instance,
                    PaddingRight = UDim.new(0, 8),
                    PaddingLeft = UDim.new(0, 8)
                })

                Items["Stroke"] = Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Notification"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Stroke1"] = Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Notification"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Notification"].Instance,
                    Position = UDim2.new(0, -8, 0, 0),
                    Size = UDim2.new(0, 1, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color
                })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Notification"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Name,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Size = UDim2.new(0, 0, 0, 15),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 2, 0.5, -1),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })
            end

            for Index, Value in Items do
                if Value.Instance:IsA("Frame") then
                    Value.Instance.BackgroundTransparency = 1
                elseif Value.Instance:IsA("TextLabel") then
                    Value.Instance.TextTransparency = 1
                elseif Value.Instance:IsA("UIStroke") then
                    Value.Instance.Transparency = 1
                end
            end

            local GetSize = function()
                local AbsSize = Items["Notification"].Instance.AbsoluteSize
                Items["Notification"].Instance.AutomaticSize = Enum.AutomaticSize.None
                task.wait()
                Items["Notification"].Instance.Size = UDim2.new(0, AbsSize.X, 0, AbsSize.Y)
                return AbsSize
            end

            local Size = GetSize()
            task.wait()
            Items["Notification"].Instance.Size = UDim2.new(0, 0, 0, Size.Y)

            local Info = TweenInfo.new(0.85, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0)

            Library:Thread(function()
                for Index, Value in Items do
                    if Value.Instance:IsA("Frame") then
                        Value:Tween({ BackgroundTransparency = 0 }, Info)
                    elseif Value.Instance:IsA("TextLabel") then
                        Value:Tween({ TextTransparency = 0 }, Info)
                    elseif Value.Instance:IsA("UIStroke") then
                        Value:Tween({ Transparency = 0 }, Info)
                    end
                end

                Items["Notification"]:Tween({ Size = UDim2.new(0, Size.X, 0, Size.Y) }, Info)

                task.delay(Duration + 0.1, function()
                    for Index, Value in Items do
                        if Value.Instance:IsA("Frame") then
                            Value:Tween({ BackgroundTransparency = 1 })
                        elseif Value.Instance:IsA("TextLabel") then
                            Value:Tween({ TextTransparency = 1 })
                        elseif Value.Instance:IsA("UIStroke") then
                            Value:Tween({ Transparency = 1 })
                        end
                    end

                    Items["Notification"]:Tween({ Size = UDim2.new(0, 0, 0, Size.Y) }, Info)
                    task.wait(0.5)
                    Items["Notification"].Instance:Destroy()
                end)
            end)
        end

        Library.ESPPreview = function(Self, Params)
            local Preview = {
                Player = nil
            }

            local AlignPreviewToWindow = function(Frame)
                local MainWindow = Library.MainWindowFrame

                if not MainWindow then
                    return
                end

                local MainPos = MainWindow.Position
                local MainSize = MainWindow.AbsoluteSize

                Frame.Position = UDim2.new(0, MainPos.X.Offset + MainSize.X + 10, 0, MainPos.Y.Offset)
            end

            local Items = {}
            do
                Items["ESPPreview"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Position = UDim2.new(0, 860, 0, 430),
                    Size = UDim2.new(0, 258, 0, 334),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["ESPPreview"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ESPPreview"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ESPPreview"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ESPPreview"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ESPPreview"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = 'Light Border' })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["ESPPreview"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params.Name,
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = UDim2.new(0, 10, 0, 6),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Accent' })

                Items["Background"] = Library:Create("TextButton", {
                    Name = "\0",
                    Parent = Items["ESPPreview"].Instance,
                    Active = false,
                    Text = "",
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 10, 0, 30),
                    Size = UDim2.new(1, -20, 1, -40),
                    Selectable = false,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Viewport"] = Library:Create("ViewportFrame", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0
                })
            end

            AlignPreviewToWindow(Items["ESPPreview"].Instance)

            local IsVisible = true
            local ApplyVisibility = function(IsWindowOpen)
                Items["ESPPreview"].Instance.Visible = IsVisible and IsWindowOpen
            end

            Library:BindToWindowVisibility(ApplyVisibility)

            function Preview:SetVisibility(Bool)
                IsVisible = Bool
                ApplyVisibility(Library.WindowOpenState)
            end

            function Preview:SetText(Text)
                Items["Text"].Instance.Text = Text
            end

            local ViewportCamera = Instance.new("Camera")

            Items["Viewport"].Instance.CurrentCamera = ViewportCamera
            ViewportCamera.CameraType = Enum.CameraType.Track
            ViewportCamera.Focus = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
            ViewportCamera.CFrame = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

            local PreviewModel = nil
            local RenderObjects = table.create(25)
            local Connections = {}

            local OFFSET = CFrame.new(0, 2.5, -8.5)

            local ValidClasses = {
                MeshPart = true,
                Part = true,
                Accoutrement = true,
                Pants = true,
                Shirt = true,
                Humanoid = true,
                BoxHandleAdornment = true,
                CylinderHandleAdornment = true,
                Highlight = true
            }

            local function DisconnectAll()
                for _, Connection in ipairs(Connections) do
                    Connection:Disconnect()
                end
                table.clear(Connections)
            end

            local function ClearViewport()
                table.clear(RenderObjects)
                for _, Obj in ipairs(Items["Viewport"].Instance:GetChildren()) do
                    if not Obj:IsA("Camera") then
                        Obj:Destroy()
                    end
                end
            end

            function Preview:RemoveObject(Object)
                local Clone = RenderObjects[Object]
                if not Clone then
                    return
                end

                RenderObjects[Object] = nil

                if Clone.Parent and Clone.Parent:IsA("Accoutrement") then
                    Clone.Parent:Destroy()
                else
                    Clone:Destroy()
                end
            end

            function Preview:AddObject(Object)
                if not Object or not ValidClasses[Object.ClassName] then
                    return
                end

                local IsArchivable = Object.Archivable
                Object.Archivable = true
                local Clone = Object:Clone()
                Object.Archivable = IsArchivable

                if Object:IsA("BasePart") then
                    RenderObjects[Object] = Clone
                elseif Object:IsA("Accoutrement") then
                    if Object:FindFirstChild("Handle") and Clone:FindFirstChild("Handle") then
                        RenderObjects[Object.Handle] = Clone.Handle
                    end
                elseif Object:IsA("Humanoid") then
                    Clone:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Running, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.StrafingNoPhysics, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
                    Clone:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
                    Clone.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                end

                return Clone
            end

            function Preview:BuildFromModel(Model)
                ClearViewport()
                DisconnectAll()

                PreviewModel = Model
                Preview.Player = Model

                if not Model then
                    return
                end

                local Viewmodel = Instance.new("Model")
                Viewmodel.Name = "Viewmodel"
                Viewmodel.Parent = Items["Viewport"].Instance

                for _, Object in ipairs(Model:GetDescendants()) do
                    local Clone = self:AddObject(Object)
                    if Clone then
                        Clone.Parent = Viewmodel
                    end
                end

                table.insert(Connections, Model.DescendantAdded:Connect(function(Object)
                    local Clone = self:AddObject(Object)
                    if Clone then
                        Clone.Parent = Viewmodel
                    end
                end))

                table.insert(Connections, Model.DescendantRemoving:Connect(function(Object)
                    self:RemoveObject(Object)
                end))
            end

            Library:Connect(RunService.Heartbeat, function()
                if not PreviewModel or not Items["ESPPreview"].Instance.Visible then
                    return
                end

                local Root = PreviewModel:FindFirstChild("HumanoidRootPart")
                if not Root then
                    return
                end

                ViewportCamera.CFrame = CFrame.new(Root.CFrame:ToWorldSpace(OFFSET).Position, Root.Position)

                for Original, Clone in pairs(RenderObjects) do
                    if Original and Original.Parent then
                        Clone.CFrame = Original.CFrame
                    else
                        Preview:RemoveObject(Original)
                    end
                end
            end)

            task.spawn(function()
                local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                Preview:BuildFromModel(Character)
            end)

            Library:Connect(LocalPlayer.CharacterAdded, function(NewCharacter)
                task.wait(1)
                Preview:BuildFromModel(NewCharacter)
            end)

            Library:RegisterLayout("ESPPreview", {
                Instance = Items["ESPPreview"].Instance
            })

            return Preview
        end

        Library.ModeratorList = function(Self, Params)
            local ModeratorList = {
                Entries = {}
            }

            local AlignModeratorListToWindow = function(Frame)
                local MainWindow = Library.MainWindowFrame

                if not MainWindow then
                    return
                end

                local MainPos = MainWindow.Position
                local MainSize = MainWindow.AbsoluteSize

                Frame.Position = UDim2.new(0, MainPos.X.Offset + MainSize.X + 10, 0, MainPos.Y.Offset + 96)
            end

            local Items = {}
            do
                Items["ModeratorList"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Position = UDim2.new(0, 860, 0, 410),
                    Size = UDim2.new(0, 228, 0, 170),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["ModeratorList"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ModeratorList"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ModeratorList"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ModeratorList"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ModeratorList"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = 'Light Border' })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["ModeratorList"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params.Name,
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = UDim2.new(0, 10, 0, 6),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Accent' })

                Items["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ModeratorList"].Instance,
                    Position = UDim2.new(0, 10, 0, 30),
                    Size = UDim2.new(1, -20, 1, -40),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Holder"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    Active = true,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 6, 0, 6),
                    Size = UDim2.new(1, -12, 1, -12),
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    AutomaticCanvasSize = Enum.AutomaticSize.None,
                    ScrollBarThickness = 1,
                    ScrollingDirection = Enum.ScrollingDirection.Y
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    Padding = UDim.new(0, 4),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Items["Empty"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Holder"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "No moderators detected",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, -2, 0, 15),
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = 'Text' })
            end

            AlignModeratorListToWindow(Items["ModeratorList"].Instance)

            local IsVisible = true
            local ApplyVisibility = function()
                Items["ModeratorList"].Instance.Visible = IsVisible
            end

            local UpdateCanvas = function()
                local Layout = Items["Holder"].Instance:FindFirstChildOfClass("UIListLayout")
                if Layout then
                    Items["Holder"].Instance.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y)
                end
            end

            local UpdateEmptyState = function()
                Items["Empty"].Instance.Visible = next(ModeratorList.Entries) == nil
                UpdateCanvas()
            end

            local Layout = Items["Holder"].Instance:FindFirstChildOfClass("UIListLayout")
            if Layout then
                Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCanvas)
            end

            function ModeratorList:SetVisibility(Bool)
                IsVisible = Bool
                ApplyVisibility()
            end

            function ModeratorList:Center()
                local AbsPos = Items["ModeratorList"].Instance.AbsolutePosition
                Items["ModeratorList"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["ModeratorList"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function ModeratorList:SetText(Text)
                Items["Text"].Instance.Text = Text
            end

            function ModeratorList:Add(PlayerName, Reason)
                local Entry = ModeratorList.Entries[PlayerName]
                if Entry then
                    Entry:Set(Reason)
                    return Entry
                end

                local EntryItems = {}
                do
                    EntryItems["Row"] = Library:Create("Frame", {
                        Name = "\0",
                        Parent = Items["Holder"].Instance,
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, -2, 0, 28),
                        BorderSizePixel = 0
                    })

                    EntryItems["Name"] = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = EntryItems["Row"].Instance,
                        TextColor3 = Library.Theme["Accent"],
                        Text = PlayerName,
                        BackgroundTransparency = 1,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Size = UDim2.new(1, 0, 0, 13),
                        BorderSizePixel = 0
                    }):AddToTheme({ TextColor3 = 'Accent' })

                    EntryItems["Reason"] = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = EntryItems["Row"].Instance,
                        TextColor3 = Library.Theme["Text"],
                        Text = Reason,
                        BackgroundTransparency = 1,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Size = UDim2.new(1, 0, 0, 13),
                        Position = UDim2.new(0, 0, 0, 15),
                        BorderSizePixel = 0
                    }):AddToTheme({ TextColor3 = 'Text' })
                end

                Entry = EntryItems

                function Entry:Set(NewReason)
                    EntryItems["Reason"].Instance.Text = NewReason
                end

                function Entry:Remove()
                    ModeratorList.Entries[PlayerName] = nil
                    EntryItems["Row"].Instance:Destroy()
                    UpdateEmptyState()
                end

                ModeratorList.Entries[PlayerName] = Entry
                UpdateEmptyState()

                return Entry
            end

            function ModeratorList:Remove(PlayerName)
                local Entry = ModeratorList.Entries[PlayerName]
                if not Entry then
                    return
                end

                ModeratorList.Entries[PlayerName] = nil
                Entry["Row"].Instance:Destroy()
                UpdateEmptyState()
            end

            function ModeratorList:Clear()
                for PlayerName, Entry in next, ModeratorList.Entries do
                    ModeratorList.Entries[PlayerName] = nil
                    Entry["Row"].Instance:Destroy()
                end

                UpdateEmptyState()
            end

            ApplyVisibility()
            UpdateEmptyState()

            Library:RegisterLayout("ModeratorList", {
                Instance = Items["ModeratorList"].Instance
            })

            return ModeratorList
        end

        Library.ConsoleLogger = function(Self, Params)
            local Logger = {}
            local CommandCallback = Params.Callback or Params.callback or function() end

            local AlignLoggerToWindow = function(Frame)
                local MainWindow = Library.MainWindowFrame

                if not MainWindow then
                    return
                end

                local MainPos = MainWindow.Position
                local MainSize = MainWindow.AbsoluteSize

                -- Match main window width, keep logger shorter, and place it clearly below the main window.
                Frame.Size = UDim2.new(0, MainSize.X, 0, 220)
                Frame.Position = UDim2.new(0, MainPos.X.Offset, 0, MainPos.Y.Offset + MainSize.Y + 10)
            end

            local Items = {}
            do
                Items["CallLogger"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Visible = true,
                    Position = UDim2.new(0, 860, 0, 132),
                    Size = UDim2.new(0, 474, 0, 262),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["CallLogger"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CallLogger"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CallLogger"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["CallLogger"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["CallLogger"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = 'Light Border' })

                Items["Title"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["CallLogger"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params.Name,
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = UDim2.new(0, 10, 0, 6),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Accent' })

                Items["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["CallLogger"].Instance,
                    Position = UDim2.new(0, 10, 0, 30),
                    Size = UDim2.new(1, -20, 1, -82),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Holder"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    Active = true,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ScrollBarImageColor3 = Library.Theme["Accent"],
                    MidImage = "rbxassetid://129030709932941",
                    ScrollBarThickness = 1,
                    Size = UDim2.new(1, -16, 1, -8),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 8, 0, 4),
                    BottomImage = "rbxassetid://129030709932941",
                    TopImage = "rbxassetid://129030709932941"
                }):AddToTheme({ ScrollBarImageColor3 = 'Accent' })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    PaddingRight = UDim.new(0, 8)
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    Padding = UDim.new(0, 0),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Items["InputBackground"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["CallLogger"].Instance,
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 10, 1, -10),
                    Size = UDim2.new(1, -20, 0, 18),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["InputBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["InputBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["InputBackground"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["Input"] = Library:Create("TextBox", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["InputBackground"].Instance,
                    PlaceholderColor3 = Library.Theme["Inactive Text"],
                    PlaceholderText = "type command and press enter",
                    TextColor3 = Library.Theme["Text"],
                    Text = "",
                    Size = UDim2.new(1, -12, 0, 15),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 6, 0.5, -7),
                    ClearTextOnFocus = false,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    CursorPosition = -1
                }):AddToTheme({ TextColor3 = 'Text' })
            end

            AlignLoggerToWindow(Items["CallLogger"].Instance)

            local IsVisible = true
            local ApplyVisibility = function(IsWindowOpen)
                Items["CallLogger"].Instance.Visible = IsVisible and IsWindowOpen
            end

            Library:BindToWindowVisibility(ApplyVisibility)

            function Logger:SetVisibility(Bool)
                IsVisible = Bool
                ApplyVisibility(Library.WindowOpenState)
            end

            function Logger:Center()
                local AbsPos = Items["CallLogger"].Instance.AbsolutePosition
                Items["CallLogger"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["CallLogger"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Logger:SetText(Text)
                Items["Title"].Instance.Text = Text
            end

            function Logger:SetCommandCallback(Callback)
                CommandCallback = Callback or function() end
            end

            function Logger:AddError(Text)
                return Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Holder"].Instance,
                    TextColor3 = Color3.fromRGB(255, 41, 45),
                    Text = Text,
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 15),
                    BorderSizePixel = 0
                })
            end

            function Logger:AddWarning(Text)
                return Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Holder"].Instance,
                    TextColor3 = Color3.fromRGB(255, 222, 32),
                    Text = Text,
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 15),
                    BorderSizePixel = 0
                })
            end

            function Logger:AddOutput(Text)
                return Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Holder"].Instance,
                    TextColor3 = Color3.fromRGB(255, 222, 32),
                    Text = Text,
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 15),
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = 'Text' })
            end

            function Logger:Clear()
                Items["InputBackground"]:ChangeItemTheme({ BackgroundColor3 = "Accent" })
                Items["InputBackground"]:Tween({ BackgroundColor3 = Library.Theme.Accent })
                task.wait(0.1)
                Items["InputBackground"]:ChangeItemTheme({ BackgroundColor3 = "Element" })
                Items["InputBackground"]:Tween({ BackgroundColor3 = Library.Theme.Element })

                for Index, Value in Items["Holder"].Instance:GetChildren() do
                    if Value:IsA("TextLabel") then
                        Value:Destroy()
                    end
                end
            end

            Items["Input"]:Connect("FocusLost", function(PressedEnter)
                if not PressedEnter then
                    return
                end

                local Text = Items["Input"].Instance.Text
                Items["Input"].Instance.Text = ""

                if Text == "" then
                    return
                end

                Library:SafeCall(CommandCallback, Text, Logger)
            end)

            Library:RegisterLayout("CallLogger", {
                Instance = Items["CallLogger"].Instance
            })

            return Logger
        end

        Library.RadarWidget = function(Self, Params)
            local Radar = {
                Entries = {},
                Range = 250,
                Visible = true
            }

            local Items = {}
            do
                Items["RadarWidget"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Visible = true,
                    Position = UDim2.new(0, 860, 0, 132),
                    Size = UDim2.new(0, 220, 0, 262),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = "Background" })

                Items["RadarWidget"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RadarWidget"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RadarWidget"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["RadarWidget"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["RadarWidget"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = "Light Border" })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["RadarWidget"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params.Name or "Radar",
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = UDim2.new(0, 10, 0, 6),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = "Accent" })

                Items["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["RadarWidget"].Instance,
                    Position = UDim2.new(0, 10, 0, 30),
                    Size = UDim2.new(1, -20, 1, -64),
                    ZIndex = 1,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["RadarBounds"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, -6),
                    Size = UDim2.new(1, -20, 1, -20),
                    ZIndex = 1,
                    BorderSizePixel = 0,
                    ClipsDescendants = true,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = "Element" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RadarBounds"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RadarBounds"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["CenterDot"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["RadarBounds"].Instance,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    Size = UDim2.new(0, 6, 0, 6),
                    ZIndex = 3,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Library:Create("UICorner", {
                    Name = "\0",
                    Parent = Items["CenterDot"].Instance,
                    CornerRadius = UDim.new(1, 0)
                })

                for _, LineData in next, {
                    { Name = "CrossX",     Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0.5, 0) },
                    { Name = "CrossY",     Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(0.5, 0, 0, 0) },
                    { Name = "GridTop",    Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0.25, 0) },
                    { Name = "GridBottom", Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0.75, 0) },
                    { Name = "GridLeft",   Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(0.25, 0, 0, 0) },
                    { Name = "GridRight",  Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(0.75, 0, 0, 0) }
                } do
                    Items[LineData.Name] = Library:Create("Frame", {
                        Name = "\0",
                        Parent = Items["RadarBounds"].Instance,
                        Size = LineData.Size,
                        Position = LineData.Position,
                        ZIndex = 2,
                        BorderSizePixel = 0,
                        BackgroundColor3 = Library.Theme["Outline"],
                        BackgroundTransparency = LineData.Name:find("Cross") and 0.3 or 0.55
                    }):AddToTheme({ BackgroundColor3 = "Outline" })
                end

                Items["Footer"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["RadarWidget"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "0 contacts | 250 studs",
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 10, 1, -8),
                    Size = UDim2.new(1, -20, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Text" })
            end

            local function ApplyVisibility()
                Items["RadarWidget"].Instance.Visible = Radar.Visible
            end

            local function CreateEntry(Key)
                local Entry = {}

                Entry.Dot = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["RadarBounds"].Instance,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    Size = UDim2.new(0, 4, 0, 4),
                    ZIndex = 4,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Library:Create("UICorner", {
                    Name = "\0",
                    Parent = Entry.Dot.Instance,
                    CornerRadius = UDim.new(0, 1)
                })

                Radar.Entries[Key] = Entry
                return Entry
            end

            Library:BindToWindowVisibility(ApplyVisibility)

            function Radar:SetVisibility(Bool)
                Radar.Visible = Bool
                ApplyVisibility()
            end

            function Radar:Center()
                local AbsPos = Items["RadarWidget"].Instance.AbsolutePosition
                Items["RadarWidget"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["RadarWidget"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Radar:SetText(Text)
                Items["Text"].Instance.Text = Text
            end

            function Radar:SetFooter(Text)
                Items["Footer"].Instance.Text = Text
            end

            function Radar:SetRange(Value)
                Radar.Range = Value
                Radar:SetFooter(("%d contacts | %d studs"):format(0, math.floor(Value or 0)))
            end

            function Radar:SetSweep(Angle)
                return Angle
            end

            function Radar:SetHeading(Angle)
                return Angle
            end

            function Radar:Upsert(Key, Data)
                local Entry = Radar.Entries[Key] or CreateEntry(Key)
                local Dot = Entry.Dot.Instance
                local Position = Data and Data.Position
                local Size = Data and Data.Size
                local Visible = Data and Data.Visible
                local Transparency = Data and Data.Transparency

                if typeof(Position) == "Vector2" then
                    Dot.Position = UDim2.new(0, Position.X, 0, Position.Y)
                end

                if typeof(Size) == "number" then
                    Dot.Size = UDim2.new(0, Size, 0, Size)
                end

                if typeof(Transparency) == "number" then
                    Dot.BackgroundTransparency = Transparency
                else
                    Dot.BackgroundTransparency = 0
                end

                Dot.Visible = Visible ~= false
                return Entry
            end

            function Radar:Remove(Key)
                local Entry = Radar.Entries[Key]
                if not Entry then
                    return
                end

                Radar.Entries[Key] = nil
                Entry.Dot.Instance:Destroy()
            end

            function Radar:Clear()
                for Key, Entry in next, Radar.Entries do
                    Radar.Entries[Key] = nil
                    Entry.Dot.Instance:Destroy()
                end
            end

            function Radar:GetBounds()
                return Items["RadarBounds"].Instance.AbsoluteSize
            end

            Radar.Items = Items

            Library:RegisterLayout("RadarWidget", {
                Instance = Items["RadarWidget"].Instance
            })

            Radar:Center()

            return Radar
        end

        Library.TargetIndicator = function(Self)
            local Indicator = {}

            local Items = {}
            do
                Items["TargetIndicator"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Position = UDim2.new(0.4242021143436432, 0, 0.7932242751121521, 0),
                    Size = UDim2.new(0, 256, 0, 80),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["TargetIndicator"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["TargetIndicator"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["TargetIndicator"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Avatar"] = Library:Create("ImageLabel", {
                    Name = "\0",
                    Parent = Items["TargetIndicator"].Instance,
                    Image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 10),
                    Size = UDim2.new(0, 60, 0, 60),
                    BorderSizePixel = 0
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Avatar"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Avatar"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Healthbar"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["TargetIndicator"].Instance,
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 80, 1, -10),
                    Size = UDim2.new(1, -90, 0, 10),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Healthbar"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["HealthbarFill"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Healthbar"].Instance,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(70, 255, 144)
                })

                Items["Value"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["HealthbarFill"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "100/100",
                    Size = UDim2.new(0, 0, 0, 15),
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -4, 0.5, -1),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Value"].Instance,
                    LineJoinMode = Enum.LineJoinMode.Miter
                })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["HealthbarFill"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["Stuff"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["TargetIndicator"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 80, 0, 10),
                    Size = UDim2.new(1, -90, 0, 15),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.Y
                })

                Items["Name"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Stuff"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "sametexe009",
                    Size = UDim2.new(1, -90, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 80, 0, 10),
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = 'Text' })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Stuff"].Instance,
                    SortOrder = Enum.SortOrder.LayoutOrder
                })
            end

            local HealthConnection = nil
            local BoundTarget = nil
            local BoundHumanoid = nil

            function Indicator:SetVisibility(Bool)
                Items["TargetIndicator"].Instance.Visible = Bool
            end

            function Indicator:Center()
                local AbsPos = Items["TargetIndicator"].Instance.AbsolutePosition
                Items["TargetIndicator"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["TargetIndicator"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Indicator:SetPosition(Position)
                Items["TargetIndicator"].Instance.AnchorPoint = Vector2.new(0, 0)
                Items["TargetIndicator"].Instance.Position = Position
            end

            function Indicator:GetBounds()
                local Instance = Items["TargetIndicator"].Instance
                return Instance.AbsolutePosition, Instance.AbsoluteSize
            end

            function Indicator:ResetConnection()
                if HealthConnection then
                    HealthConnection:Disconnect()
                    HealthConnection = nil
                end
                BoundTarget = nil
                BoundHumanoid = nil
            end

            function Indicator:SetTarget(Target)
                Indicator:ResetConnection()

                if not Target then
                    Items["Name"].Instance.Text = "No target selected"
                    Items["Avatar"].Instance.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
                    Items["Value"].Instance.Text = "0/0"
                    Items["HealthbarFill"]:Tween({ Size = UDim2.new(0, 0, 1, 0) })
                    return false
                end

                local Name = Target.Name

                Items["Name"].Instance.Text = Name
                Items["Avatar"].Instance.Image = Players:GetUserThumbnailAsync(Target.UserId, Enum.ThumbnailType
                    .HeadShot, Enum.ThumbnailSize.Size420x420)

                local Character = Target.Character
                local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
                if not Humanoid then
                    Items["Value"].Instance.Text = "0/0"
                    Items["HealthbarFill"]:Tween({ Size = UDim2.new(0, 0, 1, 0) })
                    return false
                end

                BoundTarget = Target
                BoundHumanoid = Humanoid

                local function UpdateHealth(Health)
                    if BoundTarget ~= Target or BoundHumanoid ~= Humanoid then
                        return
                    end
                    local MaxHealth = Humanoid.MaxHealth
                    local SafeMaxHealth = math.max(MaxHealth, 1)
                    local SafeHealth = math.max(Health, 0)
                    local DisplayHealth = math.floor(SafeHealth + 0.5)
                    local DisplayMaxHealth = math.floor(math.max(MaxHealth, 0) + 0.5)

                    Items["Value"].Instance.Text = DisplayHealth .. "/" .. DisplayMaxHealth

                    local HealthPercent = math.clamp(SafeHealth / SafeMaxHealth, 0, 1)
                    Items["HealthbarFill"]:Tween({ Size = UDim2.new(HealthPercent, 0, 1, 0) })
                end

                UpdateHealth(Humanoid.Health)
                HealthConnection = Humanoid.HealthChanged:Connect(UpdateHealth)
                return true
            end

            function Indicator:AddItem(Text)
                return Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Stuff"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Text,
                    Size = UDim2.new(1, -90, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 80, 0, 24),
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = 'Text' })
            end

            Library:RegisterLayout("TargetIndicator", {
                Instance = Items["TargetIndicator"].Instance
            })

            Indicator:Center()

            return Indicator
        end

        Library.ChargeShotWidget = function(Self, Params)
            local Widget = {
                Visible = false,
                Minimum = 1,
                Maximum = 30,
            }

            local Items = {}
            do
                Items["ChargeShotWidget"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Visible = false,
                    Position = UDim2.new(0.4242021143436432, 40, 0.7932242751121521, 82),
                    Size = UDim2.new(0, 176, 0, 44),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = "Background" })

                Items["ChargeShotWidget"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ChargeShotWidget"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["ChargeShotWidget"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ChargeShotWidget"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ChargeShotWidget"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = "Light Border" })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["ChargeShotWidget"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params and Params.Name or "Charge Shot",
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = UDim2.new(0, 9, 0, 6),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = "Accent" })

                Items["Value"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["ChargeShotWidget"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "x1",
                    AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, -9, 0, 6),
                    Size = UDim2.new(0, 32, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Text" })

                Items["Bar"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ChargeShotWidget"].Instance,
                    Position = UDim2.new(0, 10, 0, 26),
                    Size = UDim2.new(0, 154, 0, 8),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Bar"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Bar"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["Fill"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Bar"].Instance,
                    Size = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(255, 45, 45)
                })
            end

            local function UpdateValueText(Value)
                Items["Value"].Instance.Text = ("x%d"):format(math.floor(Value + 0.5))
            end

            function Widget:SetVisibility(Bool)
                Widget.Visible = Bool and true or false
                Items["ChargeShotWidget"].Instance.Visible = Widget.Visible
            end

            function Widget:Center()
                local AbsPos = Items["ChargeShotWidget"].Instance.AbsolutePosition
                Items["ChargeShotWidget"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["ChargeShotWidget"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Widget:SetText(Text)
                Items["Text"].Instance.Text = Text
            end

            function Widget:SetPosition(Position)
                Items["ChargeShotWidget"].Instance.AnchorPoint = Vector2.new(0, 0)
                Items["ChargeShotWidget"].Instance.Position = Position
            end

            function Widget:SetRange(Minimum, Maximum)
                Widget.Minimum = tonumber(Minimum) or 1
                Widget.Maximum = math.max(tonumber(Maximum) or 30, Widget.Minimum)
                return Widget
            end

            function Widget:SetValue(Value)
                local Min = Widget.Minimum
                local Max = Widget.Maximum
                local SafeValue = math.clamp(tonumber(Value) or Min, Min, Max)
                local Alpha = Max > Min and ((SafeValue - Min) / (Max - Min)) or 1

                Items["Fill"].Instance.Size = UDim2.new(Alpha, 0, 1, 0)
                UpdateValueText(SafeValue)
            end

            function Widget:SetAlpha(Alpha)
                local SafeAlpha = math.clamp(tonumber(Alpha) or 0, 0, 1)
                local Min = Widget.Minimum
                local Max = Widget.Maximum
                local Value = Min + ((Max - Min) * SafeAlpha)

                Items["Fill"].Instance.Size = UDim2.new(SafeAlpha, 0, 1, 0)
                UpdateValueText(Value)
            end

            function Widget:SetFillColor(Color)
                if typeof(Color) == "Color3" then
                    Items["Fill"].Instance.BackgroundColor3 = Color
                end
            end

            Widget.Items = Items

            Library:RegisterLayout("ChargeShotWidget", {
                Instance = Items["ChargeShotWidget"].Instance
            })

            Widget:Center()
            Widget:SetValue(Widget.Minimum)

            return Widget
        end

        Library.StatListWidget = function(Self, Params)
            local Widget = {
                Visible = true,
                MinimumSize = Vector2.new(208, 102),
            }

            local Items = {}
            do
                Items["StatListWidget"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Visible = true,
                    Position = UDim2.new(0, 860, 0, 916),
                    Size = UDim2.fromOffset(Widget.MinimumSize.X, Widget.MinimumSize.Y),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = "Background" })

                Items["StatListWidget"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["StatListWidget"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["StatListWidget"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["StatListWidget"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["StatListWidget"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = "Light Border" })

                Items["Title"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["StatListWidget"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params and Params.Name or "Stats",
                    Position = UDim2.new(0, 9, 0, 6),
                    Size = UDim2.new(1, -18, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Accent" })

                Items["Content"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["StatListWidget"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "",
                    Position = UDim2.new(0, 9, 0, 24),
                    Size = UDim2.new(1, -18, 1, -30),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextWrapped = false,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Text" })
            end

            local function ApplyVisibility()
                Items["StatListWidget"].Instance.Visible = Widget.Visible
            end

            Library:BindToWindowVisibility(ApplyVisibility)

            function Widget:SetVisibility(Bool)
                Widget.Visible = Bool and true or false
                ApplyVisibility()
            end

            function Widget:Center()
                local AbsPos = Items["StatListWidget"].Instance.AbsolutePosition
                Items["StatListWidget"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["StatListWidget"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Widget:SetText(Text)
                Items["Title"].Instance.Text = tostring(Text or "")
            end

            function Widget:SetPosition(Position)
                Items["StatListWidget"].Instance.AnchorPoint = Vector2.new(0, 0)
                Items["StatListWidget"].Instance.Position = Position
            end

            function Widget:SetLines(Lines)
                if type(Lines) == "table" then
                    Items["Content"].Instance.Text = table.concat(Lines, "\n")
                else
                    Items["Content"].Instance.Text = tostring(Lines or "")
                end
            end

            function Widget:GetBounds()
                local Instance = Items["StatListWidget"].Instance
                return Instance.AbsolutePosition, Instance.AbsoluteSize
            end

            Widget.Items = Items

            Library:RegisterLayout("StatListWidget", {
                Instance = Items["StatListWidget"].Instance
            })

            Widget:Center()
            Widget:SetLines({})

            return Widget
        end

        Library.InventoryViewer = function(Self, Params)
            local Viewer = {
                Visible = true,
                Entries = {},
                Sections = {},
                Columns = 4,
                MinimumSize = Vector2.new(336, 140),
                MaximumWidth = 420,
                MaximumHeight = 460,
                CellSize = Vector2.new(62, 70),
                CellPadding = 4,
                HeaderHeight = 48,
                ScrollBarThickness = 2,
                MinimumVisibleRows = 1,
                SectionSpacing = 4,
                SectionHeaderHeight = 14,
            }

            local Items = {}
            do
                Items["InventoryViewer"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Visible = true,
                    Position = UDim2.new(0, 860, 0, 776),
                    Size = UDim2.new(0, Viewer.MinimumSize.X, 0, Viewer.MinimumSize.Y),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = "Background" })

                Items["InventoryViewer"]:MakeDraggable()
                Items["InventoryViewer"]:MakeResizeable(Viewer.MinimumSize)

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["InventoryViewer"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["InventoryViewer"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["InventoryViewer"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["InventoryViewer"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = "Light Border" })

                Items["Title"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["InventoryViewer"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params and Params.Name or "Inventory Viewer",
                    Position = UDim2.new(0, 9, 0, 6),
                    Size = UDim2.new(1, -18, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Accent" })

                Items["Summary"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["InventoryViewer"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "0 items, $0",
                    Position = UDim2.new(0, 9, 0, 20),
                    Size = UDim2.new(1, -18, 0, 14),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Text" })

                Items["Target"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["InventoryViewer"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "No target selected",
                    Position = UDim2.new(0, 9, 0, 22),
                    Size = UDim2.new(1, -18, 0, 14),
                    BackgroundTransparency = 1,
                    TextTransparency = 0.35,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Text" })

                Items["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["InventoryViewer"].Instance,
                    Position = UDim2.new(0, 9, 0, Viewer.HeaderHeight),
                    Size = UDim2.new(1, -18, 1, -(Viewer.HeaderHeight + 9)),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["Holder"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    Active = true,
                    AutomaticCanvasSize = Enum.AutomaticSize.None,
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ScrollBarImageColor3 = Library.Theme["Accent"],
                    ScrollBarThickness = Viewer.ScrollBarThickness,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 8, 0, 6),
                    Size = UDim2.new(1, -18, 1, -12),
                    ScrollingDirection = Enum.ScrollingDirection.Y
                }):AddToTheme({ ScrollBarImageColor3 = "Accent" })

                Items["Content"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    AnchorPoint = Vector2.new(0.5, 0),
                    Position = UDim2.new(0.5, 0, 0, 0),
                    Size = UDim2.fromOffset(0, 0),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0
                })

                Items["ContentList"] = Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    Padding = UDim.new(0, Viewer.SectionSpacing),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })
            end

            local function ApplyVisibility()
                Items["InventoryViewer"].Instance.Visible = Viewer.Visible
            end

            local function RecalculateLayout()
                local Holder = Items["Holder"].Instance
                local Columns = math.max(math.floor(Viewer.Columns or 4), 1)
                local CellWidth = Viewer.CellSize.X
                local CellHeight = Viewer.CellSize.Y
                local Padding = Viewer.CellPadding
                local Frame = Items["InventoryViewer"].Instance
                local UsedWidth = (Columns * CellWidth) + (math.max(Columns - 1, 0) * Padding)
                local SectionWidth = UsedWidth + 12
                local ContentHeight = 0
                local VisibleSectionCount = 0

                for _, Section in ipairs(Viewer.Sections) do
                    local EntryCount = #(Section.Entries or {})
                    local Rows = EntryCount > 0 and math.max(math.ceil(EntryCount / Columns), 1) or 0
                    local GridHeight = Rows > 0 and ((Rows * CellHeight) + (math.max(Rows - 1, 0) * Padding)) or 0
                    local SectionHeight = Viewer.SectionHeaderHeight + 4

                    if Section.EmptyLabel and Section.EmptyLabel.Instance then
                        Section.EmptyLabel.Instance.Visible = EntryCount == 0
                    end
                    if Section.Content and Section.Content.Instance then
                        Section.Content.Instance.Visible = EntryCount > 0
                        Section.Content.Instance.Size = UDim2.fromOffset(UsedWidth, GridHeight)
                    end
                    if Section.Grid and Section.Grid.Instance then
                        Section.Grid.Instance.FillDirectionMaxCells = Columns
                    end
                    if Section.Title and Section.Title.Instance then
                        if EntryCount > 0 then
                            Section.Title.Instance.Text = ("%s (%d)"):format(Section.Name or "Section", EntryCount)
                        else
                            Section.Title.Instance.Text = tostring(Section.Name or "Section")
                        end
                    end

                    if EntryCount > 0 then
                        SectionHeight = SectionHeight + GridHeight + 2
                    elseif Section.EmptyLabel and Section.EmptyLabel.Instance then
                        SectionHeight = SectionHeight + 14
                    end

                    if Section.Frame and Section.Frame.Instance then
                        Section.Frame.Instance.Size = UDim2.fromOffset(SectionWidth, SectionHeight)
                    end

                    ContentHeight = ContentHeight + SectionHeight
                    VisibleSectionCount = VisibleSectionCount + 1
                end

                if VisibleSectionCount > 1 then
                    ContentHeight = ContentHeight + ((VisibleSectionCount - 1) * Viewer.SectionSpacing)
                end

                local FramePaddingX = 36
                local FramePaddingY = 21
                local AvailableHeight = math.max(Frame.AbsoluteSize.Y - Viewer.HeaderHeight - FramePaddingY, 0)
                local NeedsScrollbar = ContentHeight > (AvailableHeight + 1)
                local DesiredWidth = math.clamp(
                    SectionWidth + FramePaddingX + (NeedsScrollbar and Viewer.ScrollBarThickness or 0),
                    Viewer.MinimumSize.X,
                    Viewer.MaximumWidth
                )
                local DesiredHeight = math.clamp(ContentHeight + Viewer.HeaderHeight + FramePaddingY,
                    Viewer.MinimumSize.Y,
                    Viewer.MaximumHeight)

                Items["Content"].Instance.Size = UDim2.fromOffset(SectionWidth, ContentHeight)
                Items["Content"].Instance.Position = UDim2.new(0.5, 0, 0, 0)
                Holder.CanvasSize = UDim2.new(0, 0, 0, ContentHeight)
                Holder.ScrollBarThickness = NeedsScrollbar and Viewer.ScrollBarThickness or 0

                if math.abs(Frame.AbsoluteSize.X - DesiredWidth) > 1
                    or math.abs(Frame.AbsoluteSize.Y - DesiredHeight) > 1
                then
                    Items["InventoryViewer"]:Tween(
                        { Size = UDim2.fromOffset(DesiredWidth, DesiredHeight) },
                        TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
                    )
                end
            end

            local function ClearEntries()
                for _, Section in ipairs(Viewer.Sections) do
                    if Section and Section.Frame and Section.Frame.Instance then
                        Section.Frame.Instance:Destroy()
                    end
                end
                table.clear(Viewer.Entries)
                table.clear(Viewer.Sections)
            end

            local function CreateEntry(Section, Data)
                local Entry = {}
                local Amount = tonumber(Data.Amount) or 1
                local AmountText = Amount > 1 and ("x" .. tostring(math.floor(Amount + 0.5))) or ""

                Entry.Frame = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Section.Content.Instance,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = "Element" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Entry.Frame.Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Entry.Frame.Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Entry.Image = Library:Create("ImageLabel", {
                    Name = "\0",
                    Parent = Entry.Frame.Instance,
                    Image = Data.Image or "rbxasset://textures/ui/GuiImagePlaceholder.png",
                    AnchorPoint = Vector2.new(0.5, 0),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0, 6),
                    Size = UDim2.new(1, -14, 1, -30),
                    BorderSizePixel = 0
                })

                Entry.Image.Instance.ScaleType = Enum.ScaleType.Fit

                Entry.Name = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = math.max(Library.FontSize - 2, 9),
                    Parent = Entry.Frame.Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = tostring(Data.DisplayName or Data.Name or ""),
                    Position = UDim2.new(0, 4, 1, -22),
                    Size = UDim2.new(1, -8, 0, 12),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    TextTruncate = Enum.TextTruncate.AtEnd
                }):AddToTheme({ TextColor3 = "Text" })

                Entry.Amount = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = math.max(Library.FontSize - 2, 9),
                    Parent = Entry.Frame.Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = AmountText,
                    AnchorPoint = Vector2.new(1, 1),
                    Position = UDim2.new(1, -4, 1, -4),
                    Size = UDim2.new(1, -8, 0, 12),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Accent" })

                Viewer.Entries[#Viewer.Entries + 1] = Entry
                Section.Entries[#Section.Entries + 1] = Entry
                return Entry
            end

            local function CreateSection(Data)
                local Section = {
                    Name = tostring(Data.Name or "Section"),
                    Entries = {},
                }

                Section.Frame = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromOffset(0, 0),
                    BorderSizePixel = 0
                })

                Section.Title = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = 9,
                    Parent = Section.Frame.Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Section.Name,
                    Position = UDim2.new(0, 2, 0, 0),
                    Size = UDim2.new(1, -4, 0, Viewer.SectionHeaderHeight),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Accent" })

                Section.Divider = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Section.Frame.Instance,
                    Position = UDim2.new(0, 0, 0, Viewer.SectionHeaderHeight),
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = Library.Theme["Light Border"],
                    BorderSizePixel = 0
                }):AddToTheme({ BackgroundColor3 = "Light Border" })

                Section.Content = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Section.Frame.Instance,
                    Position = UDim2.new(0.5, 0, 0, Viewer.SectionHeaderHeight + 4),
                    AnchorPoint = Vector2.new(0.5, 0),
                    Size = UDim2.fromOffset(0, 0),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0
                })

                Section.Grid = Library:Create("UIGridLayout", {
                    Name = "\0",
                    Parent = Section.Content.Instance,
                    CellSize = UDim2.fromOffset(Viewer.CellSize.X, Viewer.CellSize.Y),
                    CellPadding = UDim2.fromOffset(Viewer.CellPadding, Viewer.CellPadding),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Section.EmptyLabel = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = math.max(Library.FontSize - 1, 10),
                    Parent = Section.Frame.Instance,
                    TextColor3 = Library.Theme["Inactive Text"],
                    Text = "None",
                    Position = UDim2.new(0, 2, 0, Viewer.SectionHeaderHeight + 5),
                    Size = UDim2.new(1, -4, 0, 12),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    Visible = false
                }):AddToTheme({ TextColor3 = "Inactive Text" })

                Viewer.Sections[#Viewer.Sections + 1] = Section
                return Section
            end

            Library:BindToWindowVisibility(ApplyVisibility)

            Items["InventoryViewer"].Instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(RecalculateLayout)
            Items["ContentList"].Instance:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(RecalculateLayout)
            Library:Connect(UserInputService.InputBegan, function(Input, Processed)
                if Processed or not Viewer.Visible then
                    return
                end

                if UserInputService:GetFocusedTextBox() then
                    return
                end

                local Holder = Items["Holder"].Instance
                local MaxScroll = math.max(Holder.CanvasSize.Y.Offset - Holder.AbsoluteWindowSize.Y, 0)
                if MaxScroll <= 0 then
                    return
                end

                local Step = Viewer.CellSize.Y + Viewer.CellPadding
                if Input.KeyCode == Enum.KeyCode.Up then
                    Holder.CanvasPosition = Vector2.new(0, math.max(Holder.CanvasPosition.Y - Step, 0))
                elseif Input.KeyCode == Enum.KeyCode.Down then
                    Holder.CanvasPosition = Vector2.new(0, math.min(Holder.CanvasPosition.Y + Step, MaxScroll))
                end
            end)

            function Viewer:SetVisibility(Bool)
                Viewer.Visible = Bool and true or false
                ApplyVisibility()
            end

            function Viewer:Center()
                local AbsPos = Items["InventoryViewer"].Instance.AbsolutePosition
                Items["InventoryViewer"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["InventoryViewer"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Viewer:SetPosition(Position)
                Items["InventoryViewer"].Instance.AnchorPoint = Vector2.new(0, 0)
                Items["InventoryViewer"].Instance.Position = Position
            end

            function Viewer:GetBounds()
                local Instance = Items["InventoryViewer"].Instance
                return Instance.AbsolutePosition, Instance.AbsoluteSize
            end

            function Viewer:SetText(Text)
                Items["Title"].Instance.Text = tostring(Text or "")
            end

            function Viewer:SetSummary(Text)
                local SummaryText = tostring(Text or "")
                local ShowSummary = SummaryText ~= ""

                Items["Summary"].Instance.Visible = ShowSummary
                Items["Summary"].Instance.Text = SummaryText
                Items["Target"].Instance.Position = ShowSummary and UDim2.new(0, 9, 0, 34) or UDim2.new(0, 9, 0, 22)
                Viewer.HeaderHeight = ShowSummary and 60 or 48
                Items["Background"].Instance.Position = UDim2.new(0, 9, 0, Viewer.HeaderHeight)
                Items["Background"].Instance.Size = UDim2.new(1, -18, 1, -(Viewer.HeaderHeight + 9))
                RecalculateLayout()
            end

            function Viewer:SetTarget(Text)
                Items["Target"].Instance.Text = tostring(Text or "")
            end

            function Viewer:Clear()
                ClearEntries()
                RecalculateLayout()
            end

            function Viewer:SetSections(List)
                ClearEntries()

                for _, SectionData in ipairs(List or {}) do
                    local Section = CreateSection(SectionData)
                    for _, Data in ipairs(SectionData.Entries or {}) do
                        CreateEntry(Section, Data)
                    end
                end

                RecalculateLayout()
            end

            function Viewer:SetItems(List)
                Viewer:SetSections({
                    {
                        Name = "Items",
                        Entries = List or {},
                    }
                })
            end

            Viewer.Items = Items

            Library:RegisterLayout("InventoryViewer", {
                Instance = Items["InventoryViewer"].Instance
            })

            Viewer:Center()
            RecalculateLayout()

            return Viewer
        end

        Library.SpotifyPlayer = function(Self)
            local Spotify = {}

            local Request = request
                or http_request
                or (syn and syn.request)
                or (getgenv and getgenv().http and getgenv().http.request)
            local GetCustomAsset = getcustomasset or getsynasset

            local SpotifyFolder = Library.Directory .. "/Spotify"
            local CacheFolder = SpotifyFolder .. "/Cache"
            local TokenPath = Library.Directory .. "/token.txt"
            local PlaceholderImage = "rbxasset://textures/ui/GuiImagePlaceholder.png"
            local PollInterval = 1

            if not isfolder(SpotifyFolder) then
                makefolder(SpotifyFolder)
            end

            if not isfolder(CacheFolder) then
                makefolder(CacheFolder)
            end

            local function ReadToken()
                if not isfile(TokenPath) then
                    writefile(TokenPath, "")
                    return ""
                end

                return (readfile(TokenPath):gsub("^%s*(.-)%s*$", "%1"))
            end

            local function DecodeTokenConfig(RawToken)
                local CleanToken = (RawToken or ""):gsub("^%s*(.-)%s*$", "%1")
                if CleanToken == "" then
                    return {
                        Raw = "",
                        AccessToken = "",
                        RefreshToken = "",
                        ClientId = "",
                        ClientSecret = "",
                        ExpiresAt = 0,
                        LyricsApi = "",
                        LyricsFormat = "raw"
                    }
                end

                if CleanToken:sub(1, 1) ~= "{" then
                    return {
                        Raw = CleanToken,
                        AccessToken = CleanToken,
                        RefreshToken = "",
                        ClientId = "",
                        ClientSecret = "",
                        ExpiresAt = math.huge,
                        LyricsApi = "",
                        LyricsFormat = "raw"
                    }
                end

                local DecodeSuccess, Parsed = pcall(HttpService.JSONDecode, HttpService, CleanToken)
                if not DecodeSuccess or type(Parsed) ~= "table" then
                    return {
                        Raw = CleanToken,
                        AccessToken = "",
                        RefreshToken = "",
                        ClientId = "",
                        ClientSecret = "",
                        ExpiresAt = 0,
                        LyricsApi = "",
                        LyricsFormat = "raw",
                        ParseFailed = true
                    }
                end

                return {
                    Raw = CleanToken,
                    AccessToken = tostring(Parsed.access_token or Parsed.token or ""):gsub("^%s*(.-)%s*$", "%1"),
                    RefreshToken = tostring(Parsed.refresh_token or ""):gsub("^%s*(.-)%s*$", "%1"),
                    ClientId = tostring(Parsed.client_id or ""):gsub("^%s*(.-)%s*$", "%1"),
                    ClientSecret = tostring(Parsed.client_secret or ""):gsub("^%s*(.-)%s*$", "%1"),
                    ExpiresAt = tonumber(Parsed.expires_at) or 0,
                    LyricsApi = tostring(Parsed.lyrics_api or ""):gsub("^%s*(.-)%s*$", "%1"),
                    LyricsFormat = tostring(Parsed.lyrics_format or "raw"):gsub("^%s*(.-)%s*$", "%1")
                }
            end

            local function EncodeTokenConfig(Config)
                if not Config then
                    return ""
                end

                if (Config.RefreshToken or "") == "" then
                    return Config.AccessToken or ""
                end

                local EncodeSuccess, Encoded = pcall(HttpService.JSONEncode, HttpService, {
                    access_token = Config.AccessToken or "",
                    refresh_token = Config.RefreshToken or "",
                    client_id = Config.ClientId or "",
                    client_secret = Config.ClientSecret or "",
                    expires_at = math.floor(tonumber(Config.ExpiresAt) or 0),
                    lyrics_api = Config.LyricsApi or "",
                    lyrics_format = Config.LyricsFormat or "raw"
                })

                return EncodeSuccess and Encoded or ""
            end

            local function WriteToken(ConfigOrToken)
                if type(ConfigOrToken) == "table" then
                    writefile(TokenPath, EncodeTokenConfig(ConfigOrToken))
                    return
                end

                writefile(TokenPath, ConfigOrToken or "")
            end

            local TokenConfig = DecodeTokenConfig(ReadToken())
            local Token = TokenConfig.AccessToken

            local CollapsedSize = UDim2.new(0, 248, 0, 88)
            local ExpandedSize = UDim2.new(0, 540, 0, 250)
            local ResultButtons = {}
            local SearchResults = {}
            local SearchTrackResults = {}
            local SearchAlbumBrowse = nil
            local CurrentTrack
            local IsExpanded = false
            local Seeking = false
            local SearchRequestId = 0
            local SearchDelay = 0.25
            local UpdateQueueCanvas

            local Items = {}
            do
                local function CreateControlButton(Key, Parent, Image, FrameSize, IconSize, IconOffsetY)
                    Items[Key] = Library:Create("TextButton", {
                        Name = "\0",
                        Parent = Parent,
                        Size = UDim2.new(0, FrameSize, 0, 20),
                        BorderSizePixel = 0,
                        AutoButtonColor = false,
                        BackgroundTransparency = 1,
                        Text = ""
                    })

                    Items[Key].Icon = Library:Create("ImageLabel", {
                        Name = "\0",
                        Parent = Items[Key].Instance,
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.new(0.5, 0, 0.5, IconOffsetY or 0),
                        Size = UDim2.new(0, IconSize, 0, IconSize),
                        BorderSizePixel = 0,
                        BackgroundTransparency = 1,
                        Image = Image,
                        ImageColor3 = Library.Theme["Text"]
                    }):AddToTheme({ ImageColor3 = "Text" })
                end

                Items["SpotifyPlayer"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Position = UDim2.new(0, 30, 0, 240),
                    Size = CollapsedSize,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"],
                    ClipsDescendants = true
                }):AddToTheme({ BackgroundColor3 = "Background" })

                Items["SpotifyPlayer"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Items["SearchBackground"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    Position = UDim2.new(0, 10, 0, -40),
                    Size = UDim2.new(0, 250, 0, 24),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = "Element" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["SearchInput"] = Library:Create("TextBox", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["SearchBackground"].Instance,
                    AnchorPoint = Vector2.new(0, 0.5),
                    PlaceholderColor3 = Library.Theme["Inactive Text"],
                    PlaceholderText = "Search songs, artists, albums",
                    Size = UDim2.new(1, -12, 0, 15),
                    TextColor3 = Library.Theme["Text"],
                    Text = "",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 6, 0.5, -1),
                    ClearTextOnFocus = false,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Text" })

                Items["SearchResults"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    Position = UDim2.new(0, 10, 0, -170),
                    Size = UDim2.new(0, 250, 0, 114),
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(),
                    ScrollBarThickness = 0,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchResults"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchResults"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["SearchResults"].Instance,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 4)
                })

                for Index = 1, 8 do
                    local Row = {}

                    Row.Frame = Library:Create("Frame", {
                        Name = "\0",
                        Parent = Items["SearchResults"].Instance,
                        Size = UDim2.new(1, -8, 0, 36),
                        BorderSizePixel = 0,
                        BackgroundTransparency = 1,
                        BackgroundColor3 = Library.Theme["Element"],
                        Visible = false
                    })

                    Row.Divider = Library:Create("Frame", {
                        Name = "\0",
                        Parent = Row.Frame.Instance,
                        AnchorPoint = Vector2.new(0.5, 1),
                        Position = UDim2.new(0.5, 0, 1, -1),
                        Size = UDim2.new(1, -22, 0, 1),
                        BorderSizePixel = 0,
                        BackgroundColor3 = Library.Theme["Outline"]
                    }):AddToTheme({ BackgroundColor3 = "Outline" })

                    Row.Cover = Library:Create("ImageLabel", {
                        Name = "\0",
                        Parent = Row.Frame.Instance,
                        Image = PlaceholderImage,
                        BackgroundTransparency = 1,
                        Size = UDim2.new(0, 30, 0, 30),
                        Position = UDim2.new(0, 3, 0, 3),
                        BorderSizePixel = 0
                    })

                    Row.Title = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = Row.Frame.Instance,
                        TextColor3 = Library.Theme["Text"],
                        Text = "",
                        BackgroundTransparency = 1,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Position = UDim2.new(0, 40, 0, 2),
                        Size = UDim2.new(1, -44, 0, 15),
                        BorderSizePixel = 0,
                        TextTruncate = Enum.TextTruncate.AtEnd
                    }):AddToTheme({ TextColor3 = "Text" })

                    Row.Album = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = Row.Frame.Instance,
                        TextColor3 = Library.Theme["Inactive Text"],
                        Text = "",
                        BackgroundTransparency = 1,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Position = UDim2.new(0, 40, 0, 17),
                        Size = UDim2.new(1, -44, 0, 14),
                        BorderSizePixel = 0,
                        TextTruncate = Enum.TextTruncate.AtEnd
                    }):AddToTheme({ TextColor3 = "Inactive Text" })

                    Row.Button = Library:Create("TextButton", {
                        Name = "\0",
                        Parent = Row.Frame.Instance,
                        Size = UDim2.new(1, 0, 1, 0),
                        BorderSizePixel = 0,
                        BackgroundTransparency = 1,
                        Text = ""
                    })

                    ResultButtons[Index] = Row
                end

                Items["LyricsFrame"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    Position = UDim2.new(1, 10, 0, 10),
                    Size = UDim2.new(0, 260, 0, 146),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["LyricsFrame"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["LyricsFrame"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["QueueLabel"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["LyricsFrame"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = "Queue",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 8, 0, 6),
                    Size = UDim2.new(1, -16, 0, 14),
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Accent" })

                Items["QueueScroll"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["LyricsFrame"].Instance,
                    Position = UDim2.new(0, 8, 0, 24),
                    Size = UDim2.new(1, -16, 1, -32),
                    BorderSizePixel = 0,
                    BackgroundTransparency = 1,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.None,
                    ScrollBarThickness = 1,
                    ScrollBarImageColor3 = Library.Theme["Border"],
                    MidImage = "rbxassetid://129030709932941",
                    BottomImage = "rbxassetid://129030709932941",
                    TopImage = "rbxassetid://129030709932941"
                }):AddToTheme({ ScrollBarImageColor3 = "Border" })

                Items["QueueText"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["QueueScroll"].Instance,
                    TextColor3 = Library.Theme["Inactive Text"],
                    Text = "Nothing is currently playing.",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    Size = UDim2.new(1, -8, 0, 0),
                    BorderSizePixel = 0,
                    TextWrapped = true,
                    RichText = true
                }):AddToTheme({ TextColor3 = "Inactive Text" })

                Library:Connect(Items["QueueScroll"].Instance:GetPropertyChangedSignal("AbsoluteSize"), function()
                    UpdateQueueCanvas()
                end)

                Items["PlayerArea"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 10),
                    Size = UDim2.new(1, -20, 0, 68),
                    BorderSizePixel = 0
                })

                Items["CoverFrame"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["PlayerArea"].Instance,
                    Position = UDim2.new(0, 0, 0, 2),
                    Size = UDim2.new(0, 50, 0, 50),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CoverFrame"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["CoverFrame"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Items["Cover"] = Library:Create("ImageLabel", {
                    Name = "\0",
                    Parent = Items["CoverFrame"].Instance,
                    Image = PlaceholderImage,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0
                })

                Items["Info"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["PlayerArea"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 60, 0, 2),
                    Size = UDim2.new(1, -176, 0, 38),
                    BorderSizePixel = 0
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Info"].Instance,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 1)
                })

                Items["Title"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Info"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "Spotify",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 14),
                    BorderSizePixel = 0,
                    TextTruncate = Enum.TextTruncate.AtEnd
                }):AddToTheme({ TextColor3 = "Text" })

                Items["Artist"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Info"].Instance,
                    TextColor3 = Library.Theme["Inactive Text"],
                    Text = "No track detected",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 13),
                    BorderSizePixel = 0,
                    TextTruncate = Enum.TextTruncate.AtEnd
                }):AddToTheme({ TextColor3 = "Inactive Text" })

                Items["Album"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Info"].Instance,
                    TextColor3 = Library.Theme["Inactive Text"],
                    Text = "Waiting for Spotify",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, 0, 0, 13),
                    BorderSizePixel = 0,
                    TextTruncate = Enum.TextTruncate.AtEnd
                }):AddToTheme({ TextColor3 = "Inactive Text" })

                Items["ProgressFrame"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    Position = UDim2.new(0, 0, 1, -3),
                    Size = UDim2.new(1, 0, 0, 3),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Library:Create("UICorner", {
                    Name = "\0",
                    Parent = Items["ProgressFrame"].Instance,
                    CornerRadius = UDim.new(1, 0)
                })

                Items["ProgressFill"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ProgressFrame"].Instance,
                    Size = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Library:Create("UICorner", {
                    Name = "\0",
                    Parent = Items["ProgressFill"].Instance,
                    CornerRadius = UDim.new(1, 0)
                })

                Items["ProgressHitbox"] = Library:Create("TextButton", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    Position = UDim2.new(0, 0, 1, -14),
                    Size = UDim2.new(1, 0, 0, 14),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Text = ""
                })

                Items["Time"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["PlayerArea"].Instance,
                    TextColor3 = Library.Theme["Inactive Text"],
                    Text = "0:00 / 0:00",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 60, 0, 40),
                    Size = UDim2.new(0, 90, 0, 15),
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = "Inactive Text" })

                Items["Controls"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["PlayerArea"].Instance,
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -18, 0.5, 12),
                    Size = UDim2.new(0, 96, 0, 24),
                    BorderSizePixel = 0
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Controls"].Instance,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalAlignment = Enum.HorizontalAlignment.Center,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 4)
                })

                CreateControlButton("Shuffle", Items["Controls"].Instance, "rbxassetid://9607545176", 12, 12, 0)
                CreateControlButton("PlayPause", Items["Controls"].Instance, "rbxassetid://9622475855", 20, 20, 0)
                CreateControlButton("Repeat", Items["Controls"].Instance, "rbxassetid://9607545605", 12, 12, 0)

                Items["ExpandButton"] = Library:Create("ImageButton", {
                    Name = "\0",
                    Parent = Items["SpotifyPlayer"].Instance,
                    AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, -8, 0, 8),
                    Size = UDim2.new(0, 14, 0, 14),
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Image = "rbxassetid://9607545497",
                    Rotation = 0,
                    ImageColor3 = Library.Theme["Text"],
                    BackgroundTransparency = 1
                }):AddToTheme({ ImageColor3 = "Text" })
            end

            local function FormatTime(Milliseconds)
                local TotalSeconds = math.max(math.floor((Milliseconds or 0) / 1000), 0)
                local Minutes = math.floor(TotalSeconds / 60)
                local Seconds = TotalSeconds % 60

                return string.format("%d:%02d", Minutes, Seconds)
            end

            local function SetProgress(Current, Total, Instant)
                local SafeTotal = math.max(Total or 0, 1)
                local Alpha = math.clamp((Current or 0) / SafeTotal, 0, 1)
                if Instant then
                    Items["ProgressFill"].Instance.Size = UDim2.new(Alpha, 0, 1, 0)
                else
                    Items["ProgressFill"]:Tween({ Size = UDim2.new(Alpha, 0, 1, 0) })
                end

                Items["Time"].Instance.Text = FormatTime(Current) .. " / " .. FormatTime(Total)
            end

            local function SetControlState(Data)
                local ShuffleEnabled = Data and Data.Shuffle
                local RepeatEnabled = Data and Data.RepeatState and Data.RepeatState ~= "off"

                Items["Shuffle"].Icon.Instance.ImageColor3 = ShuffleEnabled and Library.Theme["Accent"] or
                    Library.Theme["Text"]
                Items["Repeat"].Icon.Instance.ImageColor3 = RepeatEnabled and Library.Theme["Accent"] or
                    Library.Theme["Text"]
                Items["PlayPause"].Icon.Instance.Image = Data and Data.IsPlaying and "rbxassetid://9607545382" or
                    "rbxassetid://9622475855"
            end

            UpdateQueueCanvas = function()
                local QueueLabel = Items["QueueText"].Instance
                local QueueScroll = Items["QueueScroll"].Instance
                local Width = math.max(QueueScroll.AbsoluteSize.X - 8, 1)
                local Height = math.max(QueueLabel.TextBounds.Y + 4, QueueScroll.AbsoluteSize.Y)

                QueueLabel.Size = UDim2.new(0, Width, 0, Height)
                QueueScroll.CanvasSize = UDim2.new(0, 0, 0, Height)
            end

            local function SetQueueDisplay(Current, Tracks, EmptyText)
                if not Current and (type(Tracks) ~= "table" or #Tracks == 0) then
                    Items["QueueText"].Instance.Text = EmptyText or "No upcoming tracks."
                    UpdateQueueCanvas()
                    Items["QueueScroll"].Instance.CanvasPosition = Vector2.new()
                    return
                end

                local Buffer = {}
                if Current then
                    Buffer[#Buffer + 1] = string.format("<font color=\"#%02X%02X%02X\">Now playing</font>\n%s\n%s",
                        math.floor(Library.Theme["Accent"].R * 255),
                        math.floor(Library.Theme["Accent"].G * 255),
                        math.floor(Library.Theme["Accent"].B * 255),
                        Current.Title or "Unknown track",
                        Current.Artist or "Unknown artist")
                end

                if type(Tracks) == "table" and #Tracks > 0 then
                    if #Buffer > 0 then
                        Buffer[#Buffer + 1] = ""
                    end

                    Buffer[#Buffer + 1] = "Next up"
                end

                for Index, Track in Tracks do
                    if Index > 6 then
                        break
                    end

                    Buffer[#Buffer + 1] = string.format("%d. %s\n%s", Index, Track.Title or "Unknown track",
                        Track.Artist or "Unknown artist")
                end

                Items["QueueText"].Instance.Text = table.concat(Buffer, "\n\n")
                UpdateQueueCanvas()
                Items["QueueScroll"].Instance.CanvasPosition = Vector2.new()
            end

            local function SetDisplay(Data, EmptyText)
                if not Data then
                    CurrentTrack = nil
                    Items["Title"].Instance.Text = "Spotify"
                    Items["Artist"].Instance.Text = "No track detected"
                    Items["Album"].Instance.Text = EmptyText or "Nothing is currently playing"
                    Items["Cover"].Instance.Image = PlaceholderImage
                    SetControlState(nil)
                    SetQueueDisplay(nil, nil, "Nothing is currently playing.")
                    SetProgress(0, 0, true)
                    return
                end

                CurrentTrack = Data
                Items["Title"].Instance.Text = Data.Title
                Items["Artist"].Instance.Text = Data.Artist
                Items["Album"].Instance.Text = Data.Album
                Items["Cover"].Instance.Image = Data.Cover or PlaceholderImage
                SetControlState(Data)

                if not Seeking then
                    SetProgress(Data.Progress, Data.Duration, true)
                end
            end

            local function RefreshAccessToken()
                if not Request or TokenConfig.RefreshToken == "" then
                    return false
                end

                if TokenConfig.ClientId == "" or TokenConfig.ClientSecret == "" then
                    return false
                end

                local Body = table.concat({
                    "grant_type=refresh_token",
                    "refresh_token=" .. HttpService:UrlEncode(TokenConfig.RefreshToken),
                    "client_id=" .. HttpService:UrlEncode(TokenConfig.ClientId),
                    "client_secret=" .. HttpService:UrlEncode(TokenConfig.ClientSecret)
                }, "&")

                local Success, Response = pcall(Request, {
                    Url = "https://accounts.spotify.com/api/token",
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    },
                    Body = Body
                })

                if not Success or not Response or Response.StatusCode ~= 200 or not Response.Body or Response.Body == "" then
                    return false
                end

                local DecodeSuccess, Payload = pcall(HttpService.JSONDecode, HttpService, Response.Body)
                if not DecodeSuccess or type(Payload) ~= "table" or not Payload.access_token then
                    return false
                end

                TokenConfig.AccessToken = tostring(Payload.access_token)
                TokenConfig.ExpiresAt = tick() + math.max((tonumber(Payload.expires_in) or 3600) - 30, 0)

                if Payload.refresh_token and Payload.refresh_token ~= "" then
                    TokenConfig.RefreshToken = tostring(Payload.refresh_token)
                end

                Token = TokenConfig.AccessToken
                WriteToken(TokenConfig)
                return true
            end

            local function EnsureAccessToken()
                if TokenConfig.RefreshToken == "" then
                    Token = TokenConfig.AccessToken
                    return Token ~= ""
                end

                if TokenConfig.AccessToken ~= "" and tick() < (TokenConfig.ExpiresAt or 0) then
                    Token = TokenConfig.AccessToken
                    return true
                end

                return RefreshAccessToken()
            end

            local function MakeRequest(Url, Method, RetryOnAuthFailure, Body)
                if not Request or not EnsureAccessToken() or Token == "" then
                    return nil
                end

                local RequestBody = Body
                if type(Body) == "table" then
                    local EncodeSuccess, EncodedBody = pcall(HttpService.JSONEncode, HttpService, Body)
                    if not EncodeSuccess then
                        return nil
                    end

                    RequestBody = EncodedBody
                end

                local Success, Response = pcall(Request, {
                    Url = "https://api.spotify.com/v1/" .. Url,
                    Method = Method or "GET",
                    Headers = {
                        ["Authorization"] = "Bearer " .. Token,
                        ["Content-Type"] = "application/json"
                    },
                    Body = RequestBody
                })

                if not Success or not Response then
                    return nil
                end

                if Response.StatusCode == 401 and RetryOnAuthFailure ~= false and TokenConfig.RefreshToken ~= "" and RefreshAccessToken() then
                    return MakeRequest(Url, Method, false, Body)
                end

                if Response.StatusCode < 200 or Response.StatusCode >= 300 then
                    return nil
                end

                if not Response.Body or Response.Body == "" then
                    return true
                end

                local DecodedSuccess, Body = pcall(HttpService.JSONDecode, HttpService, Response.Body)
                return DecodedSuccess and Body or nil
            end

            local function CacheImage(Id, Url)
                if not GetCustomAsset or not Id or not Url or Url == "" then
                    return PlaceholderImage
                end

                local SafeId = tostring(Id):gsub("[^%w_%-]", "_")
                local Path = CacheFolder .. "/" .. SafeId .. ".png"

                if not isfile(Path) then
                    pcall(function()
                        writefile(Path, game:HttpGet(Url))
                    end)
                end

                if isfile(Path) then
                    local AssetSuccess, Asset = pcall(GetCustomAsset, Path)
                    if AssetSuccess then
                        return Asset
                    end
                end

                return PlaceholderImage
            end

            local function ValidateToken()
                local Data = MakeRequest("me")
                return Data and Data.display_name
            end

            local function GetCurrentTrack()
                local Data = MakeRequest("me/player")
                if not Data or not Data.item then
                    return nil
                end

                local Artists = {}
                local ArtistList = Data.item.artists or {}
                for _, Artist in ArtistList do
                    table.insert(Artists, Artist.name)
                end

                local CoverUrl = Data.item.album and Data.item.album.images and Data.item.album.images[2] and
                    Data.item.album.images[2].url

                return {
                    Title = Data.item.name or "Unknown track",
                    Artist = #Artists > 0 and table.concat(Artists, ", ") or "Unknown artist",
                    Album = Data.item.album and Data.item.album.name or "Unknown album",
                    TrackId = Data.item.id or "",
                    Progress = Data.progress_ms or 0,
                    Duration = Data.item.duration_ms or 0,
                    Cover = CacheImage(Data.item.album and Data.item.album.id or Data.item.id, CoverUrl),
                    Device = Data.device and Data.device.name or "none",
                    IsPlaying = Data.is_playing == true,
                    Shuffle = Data.shuffle_state == true,
                    RepeatState = tostring(Data.repeat_state or "off"),
                    Uri = Data.item.uri or "",
                    UpdatedAt = tick()
                }
            end

            local function GetQueue()
                local Data = MakeRequest("me/player/queue")
                local Results = {}

                if not Data or type(Data.queue) ~= "table" then
                    return Results
                end

                for _, Track in Data.queue do
                    local Artists = {}

                    for _, Artist in Track.artists or {} do
                        table.insert(Artists, Artist.name)
                    end

                    table.insert(Results, {
                        Title = Track.name or "Unknown track",
                        Artist = #Artists > 0 and table.concat(Artists, ", ") or "Unknown artist"
                    })
                end

                return Results
            end

            local function SearchTracks(Query)
                local Data = MakeRequest("search?type=track&limit=8&q=" .. HttpService:UrlEncode(Query))
                local Results = {}

                if not Data or not Data.tracks or not Data.tracks.items then
                    return Results
                end

                for _, Track in Data.tracks.items do
                    local Artists = {}
                    local CoverUrl = Track.album and Track.album.images and Track.album.images[3] and
                        Track.album.images[3].url or
                        Track.album and Track.album.images and Track.album.images[2] and Track.album.images[2].url

                    for _, Artist in Track.artists or {} do
                        table.insert(Artists, Artist.name)
                    end

                    table.insert(Results, {
                        Title = Track.name or "Unknown track",
                        Artist = #Artists > 0 and table.concat(Artists, ", ") or "Unknown artist",
                        Album = Track.album and Track.album.name or "Unknown album",
                        AlbumId = Track.album and Track.album.id or "",
                        Uri = Track.uri or "",
                        Cover = CacheImage(Track.album and Track.album.id or Track.id, CoverUrl)
                    })
                end

                return Results
            end

            local function GetAlbumTracks(AlbumId)
                local Results = {}
                if not AlbumId or AlbumId == "" then
                    return Results
                end

                local Data = MakeRequest("albums/" .. AlbumId)
                if not Data or type(Data) ~= "table" or type(Data.tracks) ~= "table" or type(Data.tracks.items) ~= "table" then
                    return Results
                end

                local CoverUrl = Data.images and Data.images[3] and Data.images[3].url or
                    Data.images and Data.images[2] and Data.images[2].url or
                    Data.images and Data.images[1] and Data.images[1].url

                for _, Track in Data.tracks.items do
                    local Artists = {}

                    for _, Artist in Track.artists or {} do
                        table.insert(Artists, Artist.name)
                    end

                    table.insert(Results, {
                        Title = Track.name or "Unknown track",
                        Artist = #Artists > 0 and table.concat(Artists, ", ") or "Unknown artist",
                        Album = Data.name or "Unknown album",
                        AlbumId = AlbumId,
                        Uri = Track.uri or "",
                        Cover = CacheImage(AlbumId, CoverUrl),
                        IsAlbumTrack = true
                    })
                end

                return Results
            end

            local function Previous()
                return MakeRequest("me/player/previous", "POST")
            end

            local function Next()
                return MakeRequest("me/player/next", "POST")
            end

            local function Resume()
                return MakeRequest("me/player/play", "PUT")
            end

            local function Pause()
                return MakeRequest("me/player/pause", "PUT")
            end

            local function Shuffle(Enabled)
                return MakeRequest("me/player/shuffle?state=" .. tostring(Enabled), "PUT")
            end

            local function Repeat(Enabled)
                return MakeRequest("me/player/repeat?state=" .. (Enabled and "context" or "off"), "PUT")
            end

            local function Seek(Milliseconds)
                return MakeRequest("me/player/seek?position_ms=" .. math.max(math.floor(Milliseconds or 0), 0), "PUT")
            end

            local function PlayUri(Uri)
                if not Uri or Uri == "" then
                    return nil
                end

                return MakeRequest("me/player/play", "PUT", true, {
                    uris = { Uri }
                })
            end

            local function UpdateResults()
                for Index, Button in ResultButtons do
                    local Result = SearchResults[Index]

                    if Result then
                        Button.Frame.Instance.Visible = true
                        Button.Cover.Instance.Image = Result.Cover or PlaceholderImage
                        Button.Title.Instance.Text = Result.Title
                        if Result.IsBack then
                            Button.Album.Instance.Text = Result.Album or "Return to search results"
                        elseif Result.IsAlbumTrack then
                            Button.Album.Instance.Text = Result.Artist
                        else
                            Button.Album.Instance.Text = Result.Album
                        end
                    else
                        Button.Frame.Instance.Visible = false
                        Button.Cover.Instance.Image = PlaceholderImage
                        Button.Title.Instance.Text = ""
                        Button.Album.Instance.Text = ""
                    end
                end
            end

            local IsVisible = true
            local LastEmptyTokenNotification = 0
            local CustomPosition = nil

            local function NotifyEmptyToken()
                if Token ~= "" or TokenConfig.RefreshToken ~= "" then
                    return
                end

                local Now = tick()
                if Now - LastEmptyTokenNotification < 1 then
                    return
                end

                LastEmptyTokenNotification = Now
                Library:Notification("Empty Spotify Token", 3, Library.Theme["Risky"])
            end

            local function ApplyVisibility()
                Items["SpotifyPlayer"].Instance.Visible = IsVisible
                if Items["SpotifyPlayer"].Instance.Visible then
                    NotifyEmptyToken()
                end
            end

            local function AlignAboveKeybindList()
                local KeyList = Library.KeyList
                local KeyListFrame = KeyList and KeyList.Items and KeyList.Items["KeybindList"] and
                    KeyList.Items["KeybindList"].Instance
                if not KeyListFrame then
                    return
                end

                local KeybindPosition = KeyListFrame.AbsolutePosition
                local SpotifyHeight = Items["SpotifyPlayer"].Instance.AbsoluteSize.Y
                Items["SpotifyPlayer"].Instance.AnchorPoint = Vector2.new(0, 0)
                Items["SpotifyPlayer"].Instance.Position = UDim2.new(0, KeybindPosition.X, 0,
                    KeybindPosition.Y - SpotifyHeight - 5)
            end

            local function SetExpanded(Bool, Instant)
                IsExpanded = Bool

                local Player = Items["SpotifyPlayer"]
                local TweenInfoValue = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
                local PlayerAreaPosition = Bool and UDim2.new(0, 10, 1, -78) or UDim2.new(0, 10, 0, 10)
                local PlayerAreaSize = Bool and UDim2.new(1, -20, 0, 68) or UDim2.new(1, -20, 0, 68)
                local SearchPosition = Bool and UDim2.new(0, 10, 0, 10) or UDim2.new(0, 10, 0, -40)
                local ResultsPosition = Bool and UDim2.new(0, 10, 0, 42) or UDim2.new(0, 10, 0, -170)
                local LyricsPosition = Bool and UDim2.new(0, 270, 0, 10) or UDim2.new(1, 10, 0, 10)
                local ExpandRotation = Bool and 90 or 0

                if Instant then
                    Player.Instance.Size = Bool and ExpandedSize or CollapsedSize
                    Items["PlayerArea"].Instance.Position = PlayerAreaPosition
                    Items["PlayerArea"].Instance.Size = PlayerAreaSize
                    Items["SearchBackground"].Instance.Position = SearchPosition
                    Items["SearchResults"].Instance.Position = ResultsPosition
                    Items["LyricsFrame"].Instance.Position = LyricsPosition
                    Items["ExpandButton"].Instance.Rotation = ExpandRotation
                else
                    Player:Tween({
                        Size = Bool and ExpandedSize or CollapsedSize
                    }, TweenInfoValue)

                    Items["PlayerArea"]:Tween({ Position = PlayerAreaPosition }, TweenInfoValue)
                    Items["PlayerArea"]:Tween({ Size = PlayerAreaSize }, TweenInfoValue)
                    Items["SearchBackground"]:Tween({ Position = SearchPosition }, TweenInfoValue)
                    Items["SearchResults"]:Tween({ Position = ResultsPosition }, TweenInfoValue)
                    Items["LyricsFrame"]:Tween({ Position = LyricsPosition }, TweenInfoValue)
                    Items["ExpandButton"]:Tween({ Rotation = ExpandRotation }, TweenInfoValue)
                end

                Spotify:Center()
            end

            local function RunSearch(Query)
                local Trimmed = (Query or ""):gsub("^%s*(.-)%s*$", "%1")
                SearchAlbumBrowse = nil

                if Trimmed == "" then
                    SearchTrackResults = {}
                    SearchResults = {}
                    UpdateResults()
                    return
                end

                SearchTrackResults = SearchTracks(Trimmed)
                SearchResults = SearchTrackResults
                UpdateResults()
            end

            local function QueueSearch(Query)
                SearchRequestId += 1
                local RequestId = SearchRequestId

                task.delay(SearchDelay, function()
                    if RequestId ~= SearchRequestId then
                        return
                    end

                    RunSearch(Query)
                end)
            end

            local function RefreshSoon()
                task.delay(0.2, function()
                    if Library and Items["SpotifyPlayer"] and Items["SpotifyPlayer"].Instance.Parent then
                        Spotify:Refresh()
                    end
                end)
            end

            local function SetSeekingFromInput(Input)
                if not CurrentTrack or not CurrentTrack.Duration or CurrentTrack.Duration <= 0 then
                    return
                end

                local Bar = Items["ProgressFrame"].Instance
                local PositionX = Input.Position and Input.Position.X or UserInputService:GetMouseLocation().X
                local Alpha = math.clamp((PositionX - Bar.AbsolutePosition.X) / math.max(Bar.AbsoluteSize.X, 1), 0,
                    1)
                local Position = math.floor(CurrentTrack.Duration * Alpha)

                CurrentTrack.Progress = Position
                CurrentTrack.UpdatedAt = tick()
                SetProgress(Position, CurrentTrack.Duration, true)
            end

            Library:BindToWindowVisibility(ApplyVisibility)

            Items["SpotifyPlayer"]:Connect("InputEnded", function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    CustomPosition = Items["SpotifyPlayer"].Instance.Position
                end
            end)

            function Spotify:SetVisibility(Bool)
                IsVisible = Bool
                ApplyVisibility()
            end

            function Spotify:Center()
                task.wait()
                if CustomPosition then
                    Items["SpotifyPlayer"].Instance.AnchorPoint = Vector2.new(0, 0)
                    Items["SpotifyPlayer"].Instance.Position = CustomPosition
                    return
                end
                AlignAboveKeybindList()
            end

            function Spotify:SetPosition(Position)
                CustomPosition = Position
                Items["SpotifyPlayer"].Instance.AnchorPoint = Vector2.new(0, 0)
                Items["SpotifyPlayer"].Instance.Position = Position
            end

            function Spotify:GetBounds()
                local Instance = Items["SpotifyPlayer"].Instance
                return Instance.AbsolutePosition, Instance.AbsoluteSize
            end

            function Spotify:SetToken(NewToken)
                TokenConfig = DecodeTokenConfig(NewToken)
                Token = TokenConfig.AccessToken
                WriteToken(TokenConfig)
                Spotify:Refresh()
            end

            function Spotify:Refresh()
                if not Request then
                    SetDisplay(nil, "Executor request API unavailable")
                    return false
                end

                if Token == "" and TokenConfig.RefreshToken == "" then
                    SetDisplay(nil, "Add a token or refresh config to niggahack/token.txt")
                    return false
                end

                if TokenConfig.RefreshToken ~= "" and (TokenConfig.ClientId == "" or TokenConfig.ClientSecret == "") then
                    SetDisplay(nil, "token.txt needs client_id and client_secret")
                    return false
                end

                if not EnsureAccessToken() then
                    SetDisplay(nil, "Could not refresh Spotify token")
                    return false
                end

                if not ValidateToken() then
                    SetDisplay(nil, "Invalid token in niggahack/token.txt")
                    return false
                end

                local Track = GetCurrentTrack()
                SetDisplay(Track, "Nothing is currently playing")
                SetQueueDisplay(Track, GetQueue(), "No upcoming tracks.")
                return Track ~= nil
            end

            for Index, Button in ResultButtons do
                Button.Button:Connect("MouseButton1Click", function()
                    local Result = SearchResults[Index]
                    if not Result then
                        return
                    end

                    if Result.IsBack then
                        SearchAlbumBrowse = nil
                        SearchResults = SearchTrackResults
                        UpdateResults()
                        return
                    end

                    if Result.IsAlbumTrack then
                        PlayUri(Result.Uri)
                        RefreshSoon()
                        return
                    end

                    SearchAlbumBrowse = Result.AlbumId
                    SearchResults = GetAlbumTracks(Result.AlbumId)

                    if #SearchResults > 0 then
                        table.insert(SearchResults, 1, {
                            Title = "< Back",
                            Album = Result.Album or "Back to results",
                            Cover = Result.Cover,
                            IsBack = true
                        })
                    end

                    UpdateResults()
                end)
            end

            Items["SearchInput"]:Connect("FocusLost", function(PressedEnter)
                if PressedEnter then
                    SearchRequestId += 1
                    RunSearch(Items["SearchInput"].Instance.Text)
                end
            end)

            Library:Connect(Items["SearchInput"].Instance:GetPropertyChangedSignal("Text"), function()
                QueueSearch(Items["SearchInput"].Instance.Text)
            end)

            Items["ExpandButton"]:Connect("MouseButton1Click", function()
                SetExpanded(not IsExpanded)
            end)

            Items["PlayPause"]:Connect("MouseButton1Click", function()
                if CurrentTrack and CurrentTrack.IsPlaying then
                    Pause()
                else
                    Resume()
                end

                RefreshSoon()
            end)

            Items["Shuffle"]:Connect("MouseButton1Click", function()
                Shuffle(not (CurrentTrack and CurrentTrack.Shuffle))
                RefreshSoon()
            end)

            Items["Repeat"]:Connect("MouseButton1Click", function()
                local RepeatEnabled = CurrentTrack and CurrentTrack.RepeatState and CurrentTrack.RepeatState ~= "off"
                Repeat(not RepeatEnabled)
                RefreshSoon()
            end)

            Items["ProgressHitbox"]:Connect("InputBegan", function(Input)
                if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end

                Seeking = true
                SetSeekingFromInput(Input)
            end)

            Library:Connect(UserInputService.InputChanged, function(Input)
                if not Seeking then
                    return
                end

                if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
                    SetSeekingFromInput(Input)
                end
            end)

            Library:Connect(UserInputService.InputEnded, function(Input)
                if not Seeking then
                    return
                end

                if Input.UserInputType ~= Enum.UserInputType.MouseButton1 and Input.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end

                Seeking = false

                if CurrentTrack then
                    Seek(CurrentTrack.Progress)
                    RefreshSoon()
                end
            end)

            Library:Thread(function()
                while Library and Items["SpotifyPlayer"] and Items["SpotifyPlayer"].Instance.Parent do
                    Spotify:Refresh()
                    task.wait(PollInterval)
                end
            end)

            Library:Thread(function()
                while Library and Items["SpotifyPlayer"] and Items["SpotifyPlayer"].Instance.Parent do
                    if Seeking and CurrentTrack then
                        SetSeekingFromInput({
                            Position = UserInputService:GetMouseLocation()
                        })
                    end

                    if CurrentTrack and CurrentTrack.IsPlaying and not Seeking then
                        local Progress = math.min(CurrentTrack.Progress + ((tick() - CurrentTrack.UpdatedAt) * 1000),
                            CurrentTrack.Duration)
                        SetProgress(Progress, CurrentTrack.Duration, true)
                    end

                    task.wait(0.1)
                end
            end)

            Library:RegisterLayout("SpotifyPlayer", {
                Instance = Items["SpotifyPlayer"].Instance
            })

            UpdateResults()
            SetExpanded(false, true)
            Spotify:Center()
            return Spotify
        end

        Library.Playerlist = function(Self, Params)
            local Playerlist = {
                Items = {},
                IsSettings = true,
                Players = {},
                Selected = nil,
            }

            local Items = {}
            do
                Items["Playerlist"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Size = UDim2.new(0, 461, 0, 403),
                    Position = UDim2.new(0, 828, 0, 99),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["Playerlist"]:MakeDraggable()

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = 'Light Border' })

                Items["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance,
                    Position = UDim2.new(0, 10, 0, 30),
                    Size = UDim2.new(1, -20, 1, -90),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["Holder"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    Active = true,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ScrollBarImageColor3 = Library.Theme["Accent"],
                    MidImage = "rbxassetid://129030709932941",
                    ScrollBarThickness = 1,
                    Size = UDim2.new(1, -16, 1, -16),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 8, 0, 8),
                    BottomImage = "rbxassetid://129030709932941",
                    TopImage = "rbxassetid://129030709932941"
                }):AddToTheme({ ScrollBarImageColor3 = 'Accent' })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    PaddingTop = UDim.new(0, -4),
                    PaddingRight = UDim.new(0, 8)
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    Padding = UDim.new(0, 8),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Items["Content"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance,
                    AnchorPoint = Vector2.new(0, 1),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 1, 0),
                    Size = UDim2.new(1, -20, 0, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.Y
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    Padding = UDim.new(0, 6),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    PaddingBottom = UDim.new(0, 10)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Playerlist"].Instance
                })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Playerlist"].Instance,
                    TextColor3 = Library.Theme["Accent"],
                    Text = Params.Name,
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = UDim2.new(0, 10, 0, 6),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Accent' })

                Playerlist.Items = Items
            end

            function Playerlist:Add(Player)
                local PlayerName = Player.Name
                local PlayerDisplay = Player.DisplayName or PlayerName
                local PlayerUserID = Player.UserId

                local PlayerItems = {}
                do
                    PlayerItems["NewPlayer"] = Library:Create("TextButton", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = Items["Holder"].Instance,
                        TextColor3 = Color3.fromRGB(0, 0, 0),
                        Text = "",
                        AutoButtonColor = false,
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, 20),
                        BorderSizePixel = 0
                    })

                    PlayerItems["Username"] = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = PlayerItems["NewPlayer"].Instance,
                        TextWrapped = true,
                        TextColor3 = Library.Theme["Text"],
                        Text = PlayerDisplay .. " (" .. PlayerName .. ")",
                        Size = UDim2.new(0, 0, 0, 15),
                        AnchorPoint = Vector2.new(0, 0.5),
                        BorderSizePixel = 0,
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 0, 0.5, 0),
                        AutomaticSize = Enum.AutomaticSize.X
                    }):AddToTheme({ TextColor3 = 'Text' })

                    PlayerItems["UserID"] = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = PlayerItems["NewPlayer"].Instance,
                        TextWrapped = true,
                        TextColor3 = Library.Theme["Text"],
                        Text = tostring(PlayerUserID),
                        Size = UDim2.new(0, 0, 0, 15),
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        BorderSizePixel = 0,
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0.5, 0, 0.5, 0),
                        AutomaticSize = Enum.AutomaticSize.X
                    }):AddToTheme({ TextColor3 = 'Text' })

                    PlayerItems["Status"] = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = PlayerItems["NewPlayer"].Instance,
                        TextWrapped = true,
                        TextColor3 = Library.Theme["Text"],
                        Text = "Neutral",
                        Size = UDim2.new(0, 0, 0, 15),
                        AnchorPoint = Vector2.new(1, 0.5),
                        BorderSizePixel = 0,
                        BackgroundTransparency = 1,
                        Position = UDim2.new(1, 0, 0.5, 0),
                        AutomaticSize = Enum.AutomaticSize.X
                    }):AddToTheme({ TextColor3 = 'Text' })
                end


                local PlayerData = {
                    Name = PlayerName,
                    Display = PlayerDisplay,
                    Player = Player,
                    Items = PlayerItems,
                    Status = "Neutral",
                    IsSelected = false,
                }

                function PlayerData:ToggleState(Status)
                    if Status == "Active" then
                        PlayerItems["Username"]:ChangeItemTheme({ TextColor3 = "Accent" })
                        PlayerItems["Username"]:Tween({ TextColor3 = Library.Theme.Accent })
                    else
                        PlayerItems["Username"]:ChangeItemTheme({ TextColor3 = "Text" })
                        PlayerItems["Username"]:Tween({ TextColor3 = Library.Theme.Text })
                    end
                end

                function PlayerData:Set()
                    PlayerData.IsSelected = not PlayerData.IsSelected

                    if PlayerData.IsSelected then
                        Playerlist.Selected = PlayerData

                        PlayerData.IsSelected = true
                        PlayerData:ToggleState("Active")

                        for Index, Value in Playerlist.Players do
                            if Value ~= PlayerData then
                                Value.IsSelected = false
                                Value:ToggleState("Inactive")
                            end
                        end
                    else
                        Playerlist.Selected = nil

                        PlayerData.IsSelected = false
                        PlayerData:ToggleState("Inactive")
                    end

                    Library:SafeCall(Playerlist.Callback, Playerlist.Selected)
                end

                PlayerData.Items.NewPlayer:Connect("MouseButton1Down", function()
                    PlayerData:Set()
                end)

                Playerlist.Players[PlayerData.Name] = PlayerData
                return PlayerData
            end

            function Playerlist:Remove(Player)
                if Playerlist.Players[Player.Name] then
                    Playerlist.Players[Player.Name].Items.NewPlayer.Instance:Destroy()
                end
            end

            function Playerlist:SetVisibility(Bool)
                Playerlist.Visible = Bool
                Items["Playerlist"].Instance.Visible = Bool and Library.WindowOpenState
            end

            function Playerlist:Center()
                local AbsPos = Items["Playerlist"].Instance.AbsolutePosition
                Items["Playerlist"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["Playerlist"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y + GuiInset)
            end

            function Playerlist:SetText(Text)
                Items["Text"].Instance.Text = Text
            end

            local StatusDropdown = Library:Dropdown({
                Name = "Status",
                Flag = "PlayerlistStatus",
                Items = { "Neutral", "Enemy", "Friendly" },
                Parent = Items["Playerlist"],
                Callback = function(Value)
                    if Playerlist.Selected then
                        local PlayerItems = Playerlist.Selected.Items

                        if PlayerItems then
                            local NeutralColor = Library.Theme.Text
                            local EnemyColor = Color3.fromRGB(255, 0, 0)
                            local FriendlyColor = Color3.fromRGB(0, 255, 0)

                            PlayerItems["Status"]:Tween({
                                TextColor3 = Value == "Enemy" and EnemyColor or Value == "Friendly" and FriendlyColor or
                                    NeutralColor
                            })

                            PlayerItems["Status"].Instance.Text = Value
                            Playerlist.Selected.Status = Value
                        end
                    end
                end
            })

            StatusDropdown.Items.Dropdown.Instance.Position = UDim2.new(0, 10, 1, -10)
            StatusDropdown.Items.Dropdown.Instance.AnchorPoint = Vector2.new(0, 1)
            StatusDropdown.Items.Dropdown.Instance.Size = UDim2.new(1, -20, 0, 40)

            for Index, Value in Players:GetPlayers() do
                Playerlist:Add(Value)
            end

            Playerlist.Visible = true
            Library:BindToWindowVisibility(function(IsWindowOpen)
                Items["Playerlist"].Instance.Visible = Playerlist.Visible and IsWindowOpen
            end)

            Library:Connect(Items["Content"].Instance.ChildAdded, function()
                task.wait()
                Items["Content"].Instance.Position = UDim2.new(0, 10, 1, Items["Content"].Instance.AbsoluteSize.Y)
            end)

            Library:Connect(Players.PlayerAdded, function(Player)
                Playerlist:Add(Player)
            end)

            Library:Connect(Players.PlayerRemoving, function(Player)
                Playerlist:Remove(Player)
            end)

            Library:RegisterLayout("Playerlist", {
                Instance = Items["Playerlist"].Instance
            })

            Playerlist:Center()

            return setmetatable(Playerlist, Library)
        end

        Library.Tooltip = function(Self, Text)
            local Object = Self.Instance

            if not Object or Text == nil then
                return
            end

            if type(Text) == "string" then
                Text = {
                    Title = "",
                    Description = Text
                }
            end

            local TitleThemeKey = Text.ColorThemeKey or Text.colorThemeKey or (Text.Risky and "Risky") or "Accent"
            local TitleText = tostring(Text.Title or "")
            local DescriptionText = tostring(Text.Description or "")
            local ShowTitle = TitleText ~= ""
            local TooltipFrame = nil
            local RenderStepped = nil

            local function DestroyTooltip()
                if RenderStepped then
                    RenderStepped:Disconnect()
                    RenderStepped = nil
                end

                if TooltipFrame then
                    TooltipFrame:Destroy()
                    TooltipFrame = nil
                end
            end

            local function CreateTooltip()
                DestroyTooltip()

                local Items = {}
                Items["Tooltip"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    Position = UDim2.new(0, 873, 0, 10),
                    BorderSizePixel = 0,
                    ZIndex = 50,
                    AutomaticSize = Enum.AutomaticSize.XY,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = "Element" })
                TooltipFrame = Items["Tooltip"].Instance

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = TooltipFrame,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = TooltipFrame,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                local TitleLabel = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = TooltipFrame,
                    ZIndex = 51,
                    TextColor3 = Library.Theme[TitleThemeKey] or Library.Theme["Accent"],
                    Text = TitleText,
                    Size = UDim2.new(0, 0, 0, 15),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X,
                    Visible = ShowTitle
                }):AddToTheme({ TextColor3 = TitleThemeKey })
                TitleLabel.Instance.Text = TitleText
                TitleLabel.Instance.Visible = ShowTitle

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = TooltipFrame,
                    PaddingTop = UDim.new(0, 4),
                    PaddingBottom = UDim.new(0, 4),
                    PaddingRight = UDim.new(0, 8),
                    PaddingLeft = UDim.new(0, 8)
                })

                local DescriptionLabel = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = TooltipFrame,
                    ZIndex = 51,
                    TextColor3 = Library.Theme["Text"],
                    Text = DescriptionText,
                    Size = UDim2.new(0, 0, 0, 15),
                    Position = ShowTitle and UDim2.new(0, 0, 0, 18) or UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = "Text" })
                DescriptionLabel.Instance.Text = DescriptionText

                local MouseLocation = UserInputService:GetMouseLocation()
                TooltipFrame.Position = UDim2.new(0, MouseLocation.X + 20, 0, MouseLocation.Y + 20)

                RenderStepped = RunService.RenderStepped:Connect(function()
                    if not TooltipFrame then
                        return
                    end

                    local UpdatedLocation = UserInputService:GetMouseLocation()
                    TooltipFrame.Position = UDim2.new(0, UpdatedLocation.X + 20, 0, UpdatedLocation.Y + 20)
                end)
            end

            Self:OnHover(CreateTooltip, DestroyTooltip)
            Library:Connect(Object.AncestryChanged, function(_, Parent)
                if Parent == nil then
                    DestroyTooltip()
                end
            end)
        end

        Library.Window = function(Self, Params)
            Params = Params or {}

            local Window = {
                IsOpen = true,
                Title = tostring(Params.Title or Params.title or Params.Name or Params.name or "Panel"),
                DockButtonText = tostring(Params.ButtonName or Params.buttonName or "Main UI"),
                Pages = {},
                Items = {}
            }

            local Items = {}
            do
                Items["MainFrame"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    Size = UDim2.new(0, 552, 0, 451),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Items["MainFrame"]:MakeDraggable()
                Items["MainFrame"]:MakeResizeable(Vector2.new(Items["MainFrame"].Instance.AbsoluteSize.X,
                    Items["MainFrame"].Instance.AbsoluteSize.Y))

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Items["AccentLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["DarkLiner"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Light Border"]
                }):AddToTheme({ BackgroundColor3 = 'Light Border' })


                Items["Shadow"] = Library:Create("ImageLabel", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    ImageColor3 = Color3.fromRGB(103, 164, 255),
                    ScaleType = Enum.ScaleType.Slice,
                    ImageTransparency = 0.699999988079071,
                    Size = UDim2.new(1, 25, 1, 25),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Image = "http://www.roblox.com/asset/?id=18245826428",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    ZIndex = -1,
                    BorderSizePixel = 0,
                    SliceCenter = Rect.new(Vector2.new(21, 21), Vector2.new(79, 79))
                }):AddToTheme({ ImageColor3 = 'Accent' })

                Items["Header"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.Holder.Instance,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Visible = true,
                    Position = UDim2.new(0, 0, 0, 0),
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                })

                Items["HeaderFirstInline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Header"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 6, 0, 26),
                    Size = UDim2.new(1, -12, 1, -36),
                    BorderSizePixel = 0,
                    ZIndex = 2,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["HeaderFirstInline"].Instance,
                    Color = Color3.fromRGB(40, 40, 45),
                    LineJoinMode = Enum.LineJoinMode.Miter
                }):AddToTheme({ Color = function() return Library.Theme["Border"] end })

                Items["HeaderSecondInline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["HeaderFirstInline"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    BorderSizePixel = 0,
                    ZIndex = 2,
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["HeaderSecondInline"].Instance,
                    Color = Color3.fromRGB(10, 10, 15),
                    LineJoinMode = Enum.LineJoinMode.Miter
                }):AddToTheme({ Color = function() return Library.Theme["Outline"] end })

                Items["HeaderAccent"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["HeaderSecondInline"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(19, 128, 225)
                }):AddToTheme({ BackgroundColor3 = "Accent" })

                Items["HeaderThirdInline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["HeaderSecondInline"].Instance,
                    Position = UDim2.new(0, 0, 0, 1),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(46, 46, 46)
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Outline"] end })

                Items["HeaderOutline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["HeaderSecondInline"].Instance,
                    Position = UDim2.new(0, 0, 0, 2),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(10, 10, 15)
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Border"] end })

                Items["HeaderInnerOutline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Header"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 6, 0, 26),
                    Size = UDim2.new(1, -12, 1, -36),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["HeaderInnerOutline"].Instance,
                    Color = Color3.fromRGB(15, 15, 20),
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Thickness = 10000
                }):AddToTheme({ Color = function() return Library.Theme["Background"] end })

                Items["HeaderTitle"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = Items["HeaderInnerOutline"].Instance,
                    FontFace = Library.Font,
                    TextColor3 = Color3.fromRGB(235, 235, 235),
                    TextStrokeColor3 = Color3.fromRGB(255, 255, 255),
                    Text = Window.Title,
                    AnchorPoint = Vector2.new(0, 1),
                    BorderSizePixel = 0,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, -1, 0, -8),
                    AutomaticSize = Enum.AutomaticSize.XY,
                    TextSize = 9,
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                }):AddToTheme({ TextColor3 = "Text" })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["HeaderTitle"].Instance,
                    LineJoinMode = Enum.LineJoinMode.Miter
                })

                Items["HeaderButtonHolder"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["HeaderInnerOutline"].Instance,
                    AnchorPoint = Vector2.new(1, 1),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, 1, 0, -6),
                    Size = UDim2.new(0, 0, 0, 16),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["HeaderButtonHolder"].Instance,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalAlignment = Enum.HorizontalAlignment.Right,
                    Padding = UDim.new(0, 7),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Items["DockOutline"] = Library:Create("TextButton", {
                    Name = "\0",
                    Parent = Items["HeaderButtonHolder"].Instance,
                    AutoButtonColor = false,
                    Active = false,
                    Selectable = false,
                    Text = "",
                    Size = UDim2.new(0, 0, 0, 16),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(46, 46, 46)
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Outline"] end })

                Items["DockInline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["DockOutline"].Instance,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(10, 10, 15)
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Border"] end })

                Items["Dock"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["DockInline"].Instance,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Color3.fromRGB(30, 30, 35)
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Section"] end })

                Items["DockText"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = Items["DockOutline"].Instance,
                    FontFace = Library.Font,
                    TextSize = 9,
                    Text = Window.DockButtonText,
                    TextColor3 = Color3.fromRGB(145, 145, 145),
                    TextStrokeColor3 = Color3.fromRGB(255, 255, 255),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.XY,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 0, 0.5, 0),
                    ZIndex = 2,
                    Size = UDim2.new(0, 0, 0, 15),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                }):AddToTheme({
                    TextColor3 = function()
                        return Window.IsOpen and Library.Theme["Text"] or Library.Theme["Inactive Text"]
                    end
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["DockText"].Instance,
                    LineJoinMode = Enum.LineJoinMode.Miter
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["DockText"].Instance,
                    PaddingLeft = UDim.new(0, 7),
                    PaddingRight = UDim.new(0, 5)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["DockInline"].Instance,
                    PaddingRight = UDim.new(0, 2)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["DockOutline"].Instance,
                    PaddingRight = UDim.new(0, 2)
                })

                Items["Header"].Instance.Visible = Window.IsOpen

                Items["PagesOutline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    Position = UDim2.new(0, 10, 0, 11),
                    Size = UDim2.new(1, -20, 0, 30),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Border 2"]
                }):AddToTheme({ BackgroundColor3 = 'Border 2' })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["PagesOutline"].Instance,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalFlex = Enum.UIFlexAlignment.Fill,
                    Padding = UDim.new(0, 1),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["PagesOutline"].Instance,
                    PaddingTop = UDim.new(0, 1),
                    PaddingBottom = UDim.new(0, 1),
                    PaddingRight = UDim.new(0, 1),
                    PaddingLeft = UDim.new(0, 1)
                })

                Items["ContentOutline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["MainFrame"].Instance,
                    Position = UDim2.new(0, 10, 0, 42),
                    Size = UDim2.new(1, -20, 1, -52),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Border 2"]
                }):AddToTheme({ BackgroundColor3 = 'Border 2' })

                Items["Content"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["ContentOutline"].Instance,
                    Position = UDim2.new(0, 2, 0, 2),
                    Size = UDim2.new(1, -4, 1, -4),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Window.Items = Items
                Library.MainWindowFrame = Items["MainFrame"].Instance
            end

            local Debounce = false

            local function CreateHeaderButton(Text, DefaultActive)
                local ButtonData = {
                    Active = DefaultActive == true
                }

                local ButtonItems = {}

                ButtonItems["Outline"] = Library:Create("TextButton", {
                    Name = "\0",
                    Parent = Items["HeaderButtonHolder"].Instance,
                    AutoButtonColor = false,
                    Active = false,
                    Selectable = false,
                    Text = "",
                    Size = UDim2.new(0, 0, 0, 16),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Outline"]
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Outline"] end })

                ButtonItems["Inline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = ButtonItems["Outline"].Instance,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Border"]
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Border"] end })

                ButtonItems["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = ButtonItems["Inline"].Instance,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = function() return Library.Theme["Section"] end })

                ButtonItems["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = ButtonItems["Outline"].Instance,
                    FontFace = Library.Font,
                    TextSize = 9,
                    Text = tostring(Text or ""),
                    TextColor3 = ButtonData.Active and Library.Theme["Text"] or Library.Theme["Inactive Text"],
                    TextStrokeColor3 = Color3.fromRGB(255, 255, 255),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.XY,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 0, 0.5, 0),
                    ZIndex = 2,
                    Size = UDim2.new(0, 0, 0, 15),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                }):AddToTheme({
                    TextColor3 = function()
                        return ButtonData.Active and Library.Theme["Text"] or Library.Theme["Inactive Text"]
                    end
                })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = ButtonItems["Text"].Instance,
                    LineJoinMode = Enum.LineJoinMode.Miter
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = ButtonItems["Text"].Instance,
                    PaddingLeft = UDim.new(0, 7),
                    PaddingRight = UDim.new(0, 5)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = ButtonItems["Inline"].Instance,
                    PaddingRight = UDim.new(0, 2)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = ButtonItems["Outline"].Instance,
                    PaddingRight = UDim.new(0, 2)
                })

                function ButtonData:SetText(Value)
                    ButtonItems["Text"].Instance.Text = tostring(Value or "")
                end

                function ButtonData:SetActive(Value)
                    ButtonData.Active = Value == true
                    ButtonItems["Text"]:Tween({
                        TextColor3 = ButtonData.Active and Library.Theme["Text"] or Library.Theme["Inactive Text"]
                    })
                end

                function ButtonData:SetVisible(Value)
                    ButtonItems["Outline"].Instance.Visible = Value == true
                end

                function ButtonData:SetCallback(Callback)
                    ButtonData.Callback = Callback
                end

                ButtonItems["Outline"]:Connect("MouseButton1Down", function()
                    if type(ButtonData.Callback) == "function" then
                        ButtonData.Callback(ButtonData)
                    end
                end)

                ButtonData.Items = ButtonItems
                return ButtonData
            end

            local function UpdateDockState()
                Items["DockText"]:Tween({
                    TextColor3 = Window.IsOpen and Library.Theme["Text"] or Library.Theme["Inactive Text"]
                })
            end

            function Window:SetOpen(Bool)
                if Debounce then
                    return
                end

                Debounce = true

                Window.IsOpen = Bool
                Items["Header"].Instance.Visible = Bool
                Library:SetWindowVisibilityState(Bool)
                Library:SetBackgroundEffectsVisible(Bool)
                UpdateDockState()

                Items["MainFrame"]:FadeDescendants(Bool, function()
                    Debounce = false
                end)
            end

            function Window:Center()
                local AbsPos = Items["MainFrame"].Instance.AbsolutePosition
                Items["MainFrame"].Instance.AnchorPoint = Vector2.new(0, 0)
                task.wait()
                Items["MainFrame"].Instance.Position = UDim2.new(0, AbsPos.X, 0, AbsPos.Y)
            end

            function Window:SetTitle(Text)
                Window.Title = tostring(Text or "Panel")
                Items["HeaderTitle"].Instance.Text = Window.Title
            end

            function Window:SetDockText(Text)
                Window.DockButtonText = tostring(Text or "Main UI")
                Items["DockText"].Instance.Text = Window.DockButtonText
            end

            function Window:AddHeaderButton(Params)
                Params = Params or {}

                local Button = CreateHeaderButton(Params.Text or Params.Name or "Button", Params.Active)
                if type(Params.Callback) == "function" then
                    Button:SetCallback(Params.Callback)
                end

                return Button
            end

            Items["DockOutline"]:Connect("MouseButton1Down", function()
                Window:SetOpen(not Window.IsOpen)
            end)

            Library:Connect(UserInputService.InputBegan, function(Input)
                if tostring(Input.KeyCode) == Library.MenuKeybind or tostring(Input.UserInputType) == Library.MenuKeybind then
                    Window:SetOpen(not Window.IsOpen)
                end
            end)

            Library:Connect(RunService.RenderStepped, function()
                if Window.IsOpen then
                    Library:GlobalUpdateOpenFrames()
                end
            end)

            Library:RegisterLayout("MainWindow", {
                Instance = Items["MainFrame"].Instance,
                SaveSize = true,
                MinimumSize = Vector2.new(552, 451)
            })

            Library:RegisterLayout("MainWindowDock", {
                Instance = Items["DockOutline"].Instance
            })

            UpdateDockState()
            Window:Center()
            return setmetatable(Window, Library)
        end

        Library.Page = function(Self, Params)
            Params = Params or {}

            local Page = {
                Name = Params.Name or Params.name or "Page",

                Window = Self,
                Items = {},
                Pages = {},
                Active = false
            }

            local Items = {}
            do
                Items["Inactive"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Page.Window.Items["PagesOutline"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Outline"]
                }):AddToTheme({ BackgroundColor3 = 'Outline' })

                Items["InactiveInline"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Inactive"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Outline"]
                }):AddToTheme({ BackgroundColor3 = 'Outline' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["InactiveInline"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["InactiveInline"].Instance,
                    TextWrapped = true,
                    TextColor3 = Library.Theme["Text"],
                    Text = Page.Name,
                    Size = UDim2.new(0, 0, 0, 15),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    BorderSizePixel = 0,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Inactive"].Instance,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border 2"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border 2' })

                Items["Page"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.UnusedHolder.Instance,
                    BackgroundTransparency = 1,
                    Visible = false,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0
                })

                Items["Columns"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Page"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0, 10),
                    Size = UDim2.new(1, 0, 1, -10),
                    BorderSizePixel = 0
                })

                Items["SubPages"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Page"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 14, 0, 0),
                    Size = UDim2.new(1, 0, 0, 20),
                    BorderSizePixel = 0
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["SubPages"].Instance,
                    FillDirection = Enum.FillDirection.Horizontal,
                    Padding = UDim.new(0, 15),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["SubPages"].Instance,
                    PaddingTop = UDim.new(0, 3)
                })

                Page.Items = Items
            end

            local Debounce = false

            function Page:Turn(Bool)
                if Debounce then
                    return
                end

                Debounce = true

                Page.Active = Bool

                if Bool then
                    Items["Text"]:ChangeItemTheme({ TextColor3 = "Accent" })
                    Items["Text"]:Tween({ TextColor3 = Library.Theme.Accent })
                else
                    Items["Text"]:ChangeItemTheme({ TextColor3 = "Text" })
                    Items["Text"]:Tween({ TextColor3 = Library.Theme.Text })
                end

                Items["Page"]:FadeDescendants(Bool, function()
                    Debounce = false

                    if Items["Page"].Instance.Visible then
                        Items["Page"].Instance.Parent = Page.Window.Items["Content"].Instance
                    else
                        Items["Page"].Instance.Parent = Library.UnusedHolder.Instance
                    end
                end)
            end

            Items["InactiveInline"]:Connect("MouseButton1Down", function()
                for Index, Value in Page.Window.Pages do
                    Value:Turn(Value == Page)
                end
            end)

            if #Page.Window.Pages == 0 then
                Page:Turn(true)
            end

            table.insert(Page.Window.Pages, Page)
            return setmetatable(Page, Library)
        end

        Library.SubPage = function(Self, Params)
            Params = Params or {}

            local Page = {
                Name = Params.Name or Params.name or "Page",

                Window = Self.Window,
                Page = Self,
                ColumnsData = {},
                Items = {},
                Active = false
            }

            local Items = {}
            do
                Items["Inactive"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Page.Page.Items["SubPages"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Page.Name,
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 15),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["Page"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Library.UnusedHolder.Instance,
                    BackgroundTransparency = 1,
                    Visible = false,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Page"].Instance,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalFlex = Enum.UIFlexAlignment.Fill,
                    Padding = UDim.new(0, 12),
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    VerticalFlex = Enum.UIFlexAlignment.Fill
                })

                Items["LeftColumn"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["Page"].Instance,
                    ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0),
                    Active = true,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = 0,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 100, 0, 100),
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["LeftColumn"].Instance,
                    PaddingTop = UDim.new(0, 14),
                    PaddingLeft = UDim.new(0, 14),
                    PaddingBottom = UDim.new(0, 14)
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["LeftColumn"].Instance,
                    Padding = UDim.new(0, 14),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Items["RightColumn"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["Page"].Instance,
                    ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0),
                    Active = true,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = 0,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 100, 0, 100),
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0)
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["RightColumn"].Instance,
                    PaddingTop = UDim.new(0, 14),
                    PaddingRight = UDim.new(0, 14),
                    PaddingBottom = UDim.new(0, 14)
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["RightColumn"].Instance,
                    Padding = UDim.new(0, 14),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Page.ColumnsData[1] = Items["LeftColumn"]
                Page.ColumnsData[2] = Items["RightColumn"]

                Page.Items = Items
            end

            local Debounce = false

            function Page:Turn(Bool)
                if Debounce then
                    return
                end

                Page.Active = Bool

                Debounce = true

                if Bool then
                    Items["Inactive"]:ChangeItemTheme({ TextColor3 = "Accent" })
                    Items["Inactive"]:Tween({ TextColor3 = Library.Theme.Accent })
                else
                    Items["Inactive"]:ChangeItemTheme({ TextColor3 = "Text" })
                    Items["Inactive"]:Tween({ TextColor3 = Library.Theme.Text })
                end

                Items["Page"]:FadeDescendants(Bool, function()
                    Debounce = false

                    if Items["Page"].Instance.Visible then
                        Items["Page"].Instance.Parent = Page.Page.Items["Columns"].Instance
                    else
                        Items["Page"].Instance.Parent = Library.UnusedHolder.Instance
                    end
                end)
            end

            Items["Inactive"]:Connect("MouseButton1Down", function()
                for Index, Value in Page.Page.Pages do
                    Value:Turn(Value == Page)
                end
            end)

            if #Page.Page.Pages == 0 then
                Page:Turn(true)
            end

            table.insert(Page.Page.Pages, Page)
            return setmetatable(Page, Library)
        end

        Library.Section = function(Self, Params)
            Params = Params or {}

            local Section = {
                Name = Params.Name or Params.name or "Section",
                Side = Params.Side or Params.side or 1,

                Window = Self.Window,
                Page = Self,
                Items = {},
            }

            local Items = {}
            do
                Items["SectionOutline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Section.Page.ColumnsData[Section.Side].Instance,
                    Size = UDim2.new(1, 0, 0, 20),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Library.Theme["Outline"]
                }):AddToTheme({ BackgroundColor3 = 'Outline' })

                Items["Section"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["SectionOutline"].Instance,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Items["Content"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Section"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 36, 0, 15),
                    Size = UDim2.new(1, -72, 0, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.Y
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    Padding = UDim.new(0, 7),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Content"].Instance,
                    PaddingBottom = UDim.new(0, 20)
                })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["SectionOutline"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Section.Name,
                    Size = UDim2.new(0, 0, 0, 4),
                    Position = UDim2.new(0, 6, 0, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Library.Theme["Section"]
                }):AddToTheme({ BackgroundColor3 = 'Section' })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Text"].Instance,
                    PaddingRight = UDim.new(0, 4),
                    PaddingLeft = UDim.new(0, 4)
                })

                Section.Items = Items
            end

            return setmetatable(Section, Library)
        end

        Library.Toggle = function(Self, Params)
            Params = Params or {}

            local Toggle = {
                Name = Params.Name or Params.name or "Toggle",
                Flag = Params.Flag or Params.flag or (Params.Name or Params.name),
                Default = Params.Default or Params.default or false,
                Risky = Params.Risky or Params.risky or false,
                Tooltip = Params.Tooltip or Params.tooltip or nil,
                Callback = Params.Callback or Params.callback or function() end,

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,

                Value = false,
                Items = {}
            }

            local Parent

            if Params.Parent then
                Parent = Params.Parent
            else
                Parent = Toggle.Section.Items["Content"]
            end

            local Items = {}
            local ToggleButtonOffset = Toggle.Section.IsSettings and 0 or 20
            local ToggleTextOffset = Toggle.Section.IsSettings and 14 or 20
            do
                Items["Toggle"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Parent.Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, -ToggleButtonOffset, 0, 0),
                    Size = UDim2.new(1, ToggleButtonOffset, 0, 12),
                    BorderSizePixel = 0
                })

                local TooltipData = Toggle.Tooltip
                if Toggle.Risky and typeof(Toggle.Tooltip) == "table" then
                    TooltipData = table.clone(Toggle.Tooltip)
                    TooltipData.Risky = true
                end
                Items["Toggle"]:Tooltip(TooltipData)

                Items["Indicator"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Toggle"].Instance,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 0, 0.5, 0),
                    Size = UDim2.new(0, 8, 0, 8),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Indicator"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Items["Inline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Indicator"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Toggle"].Instance,
                    TextColor3 = Color3.fromRGB(100, 100, 100),
                    Text = Toggle.Name,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Size = UDim2.new(0, 0, 0, 12),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, ToggleTextOffset, 0.5, -2),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Inactive Text' })

                if Toggle.Risky then
                    Items["Text"]:ChangeItemTheme({ TextColor3 = "Risky" })
                    Items["Text"].Instance.TextColor3 = Library.Theme["Risky"]
                end

                Items["SubElements"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Toggle"].Instance,
                    AnchorPoint = Vector2.new(1, 0),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, 0, 0, 0),
                    Size = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["SubElements"].Instance,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalAlignment = Enum.HorizontalAlignment.Right,
                    Padding = UDim.new(0, 6),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Items["Toggle"]:OnHover(function()
                    Items["Indicator"]:Tween({ BackgroundColor3 = Library.Theme["Hovered Element"] })
                end, function()
                    Items["Indicator"]:Tween({ BackgroundColor3 = Library.Theme["Element"] })
                end)

                Toggle.Items = Items
            end

            function Toggle:Set(Bool)
                Toggle.Value = Bool

                if Bool then
                    Items["Inline"]:Tween({ BackgroundTransparency = 0, Size = UDim2.new(1, 0, 1, 0) })
                    if not Toggle.Risky then
                        Items["Text"]:ChangeItemTheme({ TextColor3 = "Text" })
                        Items["Text"]:Tween({ TextColor3 = Library.Theme.Text })
                    end
                else
                    Items["Inline"]:Tween({ BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0) })
                    if not Toggle.Risky then
                        Items["Text"]:ChangeItemTheme({ TextColor3 = "Inactive Text" })
                        Items["Text"]:Tween({ TextColor3 = Library.Theme["Inactive Text"] })
                    end
                end

                Flags[Toggle.Flag] = Bool
                Library:SafeCall(Toggle.Callback, Bool)
            end

            function Toggle:SetVisibility(Bool)
                Items["Toggle"].Instance.Visible = Bool
            end

            function Toggle:SetText(Text)
                Items["Text"].Instance.Text = tostring(Text)
            end

            function Toggle:Settings()
                local Settingss = {
                    IsSettings = true
                }

                Items["SettingsButton"] = Library:Create("ImageButton", {
                    Name = "\0",
                    Parent = Items["SubElements"].Instance,
                    ImageColor3 = Library.Theme["Text"],
                    AutoButtonColor = false,
                    Image = "rbxassetid://124244905334583",
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 12, 0, 12),
                    BorderSizePixel = 0
                }):AddToTheme({ ImageColor3 = 'Text' })

                local SettingsItems = {
                    IsOpen = false,
                    Items = {},
                }
                do
                    SettingsItems["ToggleSettings"] = Library:Create("Frame", {
                        Name = "\0",
                        Parent = Library.UnusedHolder.Instance,
                        Position = UDim2.new(0.5156353712081909, 0, 0.08411215990781784, 0),
                        Visible = false,
                        Size = UDim2.new(0, 254, 0, 242),
                        BorderSizePixel = 0,
                        BackgroundColor3 = Library.Theme["Background"]
                    }):AddToTheme({ BackgroundColor3 = 'Background' })

                    Library:Create("UIStroke", {
                        Name = "\0",
                        Parent = SettingsItems["ToggleSettings"].Instance,
                        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                        LineJoinMode = Enum.LineJoinMode.Miter,
                        Color = Library.Theme["Outline"]
                    }):AddToTheme({ Color = 'Outline' })

                    Library:Create("UIStroke", {
                        Name = "\0",
                        Parent = SettingsItems["ToggleSettings"].Instance,
                        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                        LineJoinMode = Enum.LineJoinMode.Miter,
                        Color = Library.Theme["Border"],
                        BorderOffset = UDim.new(0, 1)
                    }):AddToTheme({ Color = 'Border' })

                    SettingsItems["Text"] = Library:Create("TextLabel", {
                        Name = "\0",
                        FontFace = Library.Font,
                        TextSize = Library.FontSize,
                        Parent = SettingsItems["ToggleSettings"].Instance,
                        TextColor3 = Library.Theme["Text"],
                        Text = Toggle.Name,
                        Size = UDim2.new(0, 0, 0, 12),
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 28, 0, 9),
                        BorderSizePixel = 0,
                        AutomaticSize = Enum.AutomaticSize.X
                    }):AddToTheme({ TextColor3 = 'Text' })

                    SettingsItems["Content"] = Library:Create("ScrollingFrame", {
                        Name = "\0",
                        Parent = SettingsItems["ToggleSettings"].Instance,
                        AutomaticCanvasSize = Enum.AutomaticSize.Y,
                        BorderSizePixel = 0,
                        CanvasSize = UDim2.new(0, 0, 0, 0),
                        MidImage = "rbxassetid://86870199131153",
                        ClipsDescendants = true,
                        ScrollBarThickness = 2,
                        Size = UDim2.new(1, 0, 1, -30),
                        Selectable = false,
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 0, 0, 30),
                        BottomImage = "rbxassetid://86870199131153",
                        TopImage = "rbxassetid://86870199131153"
                    })

                    Library:Create("UIPadding", {
                        Name = "\0",
                        Parent = SettingsItems["Content"].Instance,
                        PaddingTop = UDim.new(0, 5),
                        PaddingBottom = UDim.new(0, 5),
                        PaddingRight = UDim.new(0, 10),
                        PaddingLeft = UDim.new(0, 10)
                    })

                    Library:Create("UIListLayout", {
                        Name = "\0",
                        Parent = SettingsItems["Content"].Instance,
                        Padding = UDim.new(0, 5),
                        SortOrder = Enum.SortOrder.LayoutOrder
                    })

                    SettingsItems["SettingsButton"] = Library:Create("ImageButton", {
                        Name = "\0",
                        Parent = SettingsItems["ToggleSettings"].Instance,
                        ImageColor3 = Library.Theme["Text"],
                        AutoButtonColor = false,
                        Image = "rbxassetid://124244905334583",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 10, 0, 10),
                        Size = UDim2.new(0, 12, 0, 12),
                        BorderSizePixel = 0
                    }):AddToTheme({ ImageColor3 = 'Text' })

                    Settingss.Items = SettingsItems
                end

                local Debounce = false
                local RenderStepped
                local SettingsHolder = SettingsItems["ToggleSettings"].Instance
                local SettingsButton = Items["SettingsButton"].Instance

                Settingss.AttachedButton = SettingsButton
                Settingss.CanUpdateNow = false
                Settingss.Frame = SettingsHolder

                function Settingss:SetOpen(Bool)
                    if Debounce then
                        return
                    end

                    Settingss.IsOpen = Bool

                    Debounce = true

                    if Settingss.IsOpen then
                        SettingsHolder.Position = UDim2.new(0, SettingsButton.AbsolutePosition.X, 0,
                            SettingsButton.AbsolutePosition.Y + SettingsButton.AbsoluteSize.Y + GuiInset)

                        SettingsHolder.Parent = Library.Holder.Instance
                        SettingsHolder.Visible = true
                        SettingsItems["ToggleSettings"]:Tween({
                            Position = UDim2.new(0, SettingsButton.AbsolutePosition
                                .X, 0, SettingsButton.AbsolutePosition.Y + SettingsButton.AbsoluteSize.Y + 10 + GuiInset)
                        })

                        SettingsItems["ToggleSettings"]:FadeDescendants(true, function()
                            Debounce = false
                            Settingss.CanUpdateNow = true
                        end)

                        for Index, Value in Library.OpenFrames do
                            Value:SetOpen(false)
                        end

                        Library.OpenFrames[Settingss] = Settingss
                    else
                        for _, OpenFrame in Library.OpenFrames do
                            if OpenFrame
                                and OpenFrame ~= Settingss
                                and OpenFrame.IsOpen
                                and OpenFrame.SetOpen
                                and OpenFrame.AttachedButton
                                and OpenFrame.AttachedButton:IsDescendantOf(SettingsHolder)
                            then
                                OpenFrame:SetOpen(false)
                            end
                        end

                        for _, OpenFrame in Library.OpenFrames do
                            if OpenFrame and OpenFrame ~= Settingss and OpenFrame.IsOpen and OpenFrame.SetOpen then
                                OpenFrame:SetOpen(false)
                            end
                        end

                        SettingsItems["ToggleSettings"]:Tween({
                            Position = UDim2.new(0, SettingsButton.AbsolutePosition
                                .X, 0, SettingsButton.AbsolutePosition.Y + SettingsButton.AbsoluteSize.Y - 10 + GuiInset)
                        })
                        SettingsItems["ToggleSettings"]:FadeDescendants(false, function()
                            SettingsHolder.Parent = Library.UnusedHolder.Instance
                            Debounce = false
                            Settingss.CanUpdateNow = false
                        end)

                        if Library.OpenFrames[Settingss] then
                            Library.OpenFrames[Settingss] = nil
                        end

                        if RenderStepped then
                            RenderStepped:Disconnect()
                            RenderStepped = nil
                        end
                    end

                    local Descendants = SettingsHolder:GetDescendants()
                    table.insert(Descendants, SettingsHolder)

                    for Index, Value in Descendants do
                        if Value.ClassName:find("UI") then
                            continue
                        end

                        Value.ZIndex = Settingss.IsOpen and 2 or 1
                    end
                end

                Items["SettingsButton"]:Connect("MouseButton1Down", function()
                    Settingss:SetOpen(not Settingss.IsOpen)
                end)

                Library:Connect(UserInputService.InputBegan, function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                        if Settingss.IsOpen then
                            if SettingsItems["ToggleSettings"]:IsMouseOverFrame() then
                                return
                            end

                            for _, OpenFrame in Library.OpenFrames do
                                if OpenFrame
                                    and OpenFrame ~= Settingss
                                    and OpenFrame.IsOpen
                                    and OpenFrame.Frame
                                    and OpenFrame.Frame:IsMouseOverFrame()
                                then
                                    return
                                end
                            end

                            Settingss:SetOpen(false)
                        end
                    end
                end)

                return setmetatable(Settingss, Library)
            end

            function Toggle:Colorpicker(Data)
                Data = Data or {}

                local Colorpicker = {
                    Flag = Data.Flag or Data.flag or (Data.Name or Data.name or Toggle.Name),
                    Default = Data.Default or Data.default or Color3.fromRGB(255, 255, 255),
                    Callback = Data.Callback or Data.callback or function() end,
                    Alpha = Data.Alpha or Data.alpha or 0,

                    Window = Toggle.Window,
                    Page = Toggle.Page,
                    Section = Toggle.Section,
                }

                local NewColorpicker, ColorpickerItems = Library:CreateColorpicker({
                    Parent = Items["SubElements"],
                    Page = Colorpicker.Page,
                    Section = Colorpicker.Section,
                    Flag = Colorpicker.Flag,
                    Default = Colorpicker.Default,
                    Callback = Colorpicker.Callback,
                    Alpha = Colorpicker.Alpha
                })

                return NewColorpicker
            end

            function Toggle:Keybind(Data)
                Data = Data or {}

                local Keybind = {
                    Name = Data.Name or Data.name or Toggle.Name,
                    Flag = Data.Flag or Data.flag or (Data.Name or Data.name or Toggle.Name),
                    Default = Data.Default or Data.default,
                    Callback = Data.Callback or Data.callback or function() end,
                    Mode = Data.Mode or Data.mode or "Toggle",

                    Window = Toggle.Window,
                    Page = Toggle.Page,
                    Section = Toggle.Section,
                }

                local NewKeybind, KeybindItems = Library:CreateKeybind({
                    Parent = Items["SubElements"],
                    Name = Keybind.Name,
                    Page = Keybind.Page,
                    Section = Keybind.Section,
                    Flag = Keybind.Flag,
                    Default = Keybind.Default,
                    Mode = Keybind.Mode,
                    Callback = Keybind.Callback
                })

                return NewKeybind
            end

            Items["Toggle"]:Connect("MouseButton1Down", function()
                Toggle:Set(not Toggle.Value)
            end)

            Toggle:Set(Toggle.Default)

            SetFlags[Toggle.Flag] = function(Value)
                Toggle:Set(Value)
            end

            return setmetatable(Toggle, Library)
        end

        Library.Button = function(Self, Params)
            Params = Params or {}

            local Button = {
                Name = Params.Name or Params.name or "Button",
                Callback = Params.Callback or Params.callback or function() end,
                Tooltip = Params.Tooltip or Params.tooltip or nil,

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,
                Items = {}
            }

            local Items = {}
            do
                Items["Button"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Button.Section.Items["Content"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Size = UDim2.new(1, 0, 0, 18),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Items["Button"]:Tooltip(Button.Tooltip)

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Button"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Button"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["Button"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Button"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Button.Name,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Size = UDim2.new(0, 0, 0, 15),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0.5, -1),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["Button"]:OnHover(function()
                    Items["Button"]:Tween({ BackgroundColor3 = Library.Theme["Hovered Element"] })
                end, function()
                    Items["Button"]:Tween({ BackgroundColor3 = Library.Theme["Element"] })
                end)

                Button.Items = Items
            end

            function Button:Press()
                Items["Button"]:ChangeItemTheme({ BackgroundColor3 = "Accent" })
                Items["Button"]:Tween({ BackgroundColor3 = Library.Theme.Accent })
                task.wait(0.1)
                Items["Button"]:ChangeItemTheme({ BackgroundColor3 = "Element" })
                Items["Button"]:Tween({ BackgroundColor3 = Library.Theme.Element })

                Library:SafeCall(Button.Callback)
            end

            function Button:SetVisibility(Bool)
                Items["Button"].Instance.Visible = Bool
            end

            function Button:SetText(Text)
                Items["Text"].Instance.Text = tostring(Text)
            end

            Items["Button"]:Connect("MouseButton1Down", function()
                Button:Press()
            end)

            return setmetatable(Button, Library)
        end

        Library.Slider = function(Self, Params)
            Params = Params or {}

            local Slider = {
                Name = Params.Name or Params.name or "Slider",
                Flag = Params.Flag or Params.flag or (Params.Name or Params.name),
                Default = Params.Default or Params.default or 0,
                Min = Params.Min or Params.min or 0,
                Tooltip = Params.Tooltip or Params.tooltip or nil,
                Max = Params.Max or Params.max or 100,
                Callback = Params.Callback or Params.callback or function() end,
                Decimals = Params.Decimals or Params.decimals or 0,
                Suffix = Params.Suffix or Params.suffix or "",

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,

                Value = 0,
                Sliding = false,
                Items = {}
            }

            local Items = {}
            do
                Items["Slider"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Slider.Section.Items["Content"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 25),
                    BorderSizePixel = 0
                })

                Items["Slider"]:Tooltip(Slider.Tooltip)

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Slider"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Slider.Name,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 12),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["RealSlider"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Slider"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 0, 1, 0),
                    Size = UDim2.new(1, 0, 0, 6),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RealSlider"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"]
                }):AddToTheme({ Color = 'Border' })

                Items["Accent"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["RealSlider"].Instance,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Accent"]
                }):AddToTheme({ BackgroundColor3 = 'Accent' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["Accent"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["Value"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Accent"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "100%",
                    AnchorPoint = Vector2.new(1, 0),
                    Size = UDim2.new(0, 0, 0, 12),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, 0, 0, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Value"].Instance,
                    LineJoinMode = Enum.LineJoinMode.Miter
                })

                Items["RealSlider"]:OnHover(function()
                    Items["RealSlider"]:Tween({ BackgroundColor3 = Library.Theme["Hovered Element"] })
                end, function()
                    Items["RealSlider"]:Tween({ BackgroundColor3 = Library.Theme["Element"] })
                end)

                Slider.Items = Items
            end

            function Slider:Set(Value)
                Slider.Value = Library:Round(math.clamp(Value, Slider.Min, Slider.Max), Slider.Decimals)

                Items["Accent"]:Tween(
                    { Size = UDim2.new((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min), 0, 1, 0) },
                    TweenInfo.new(Library.Animation.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
                Items["Value"].Instance.Text = string.format("%s%s", Slider.Value, Slider.Suffix)

                Flags[Slider.Flag] = Slider.Value
                Library:SafeCall(Slider.Callback, Slider.Value)
            end

            function Slider:SetVisibility(Bool)
                Items["Slider"].Instance.Visible = Bool
            end

            function Slider:GetSize(Input)
                local SizeX = (Input.Position.X - Items["RealSlider"].Instance.AbsolutePosition.X) /
                    Items["RealSlider"].Instance.AbsoluteSize.X
                local Value = ((Slider.Max - Slider.Min) * SizeX) + Slider.Min

                return Value
            end

            function Slider:SetText(Text)
                Items["Text"].Instance.Text = tostring(Text)
            end

            local InputChanged

            Items["RealSlider"]:Connect("InputBegan", function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    Slider.Sliding = true

                    local Value = Slider:GetSize(Input)

                    Slider:Set(Value)

                    if InputChanged then
                        return
                    end

                    InputChanged = Input.Changed:Connect(function()
                        if Input.UserInputState == Enum.UserInputState.End then
                            Slider.Sliding = false

                            InputChanged:Disconnect()
                            InputChanged = nil
                        end
                    end)
                end
            end)

            Library:Connect(UserInputService.InputChanged, function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
                    if Slider.Sliding then
                        local Value = Slider:GetSize(Input)

                        Slider:Set(Value)
                    end
                end
            end)

            Slider:Set(Slider.Default)

            SetFlags[Slider.Flag] = function(Value)
                Slider:Set(Value)
            end

            return setmetatable(Slider, Library)
        end

        Library.Dropdown = function(Self, Params)
            Params = Params or {}

            local Dropdown = {
                Name = Params.Name or Params.name or "Dropdown",
                OptionItems = Params.Items or Params.items or {},
                Tooltip = Params.Tooltip or Params.tooltip or nil,
                Flag = Params.Flag or Params.flag or (Params.Name or Params.name),
                Default = Params.Default or Params.default or "",
                Callback = Params.Callback or Params.callback or function() end,
                Multi = Params.Multi or Params.multi or false,

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,

                Value = {},
                Options = {},
                IsOpen = false,
                Items = {}
            }

            local Parent

            if Params.Parent then
                Parent = Params.Parent
            else
                Parent = Dropdown.Section.Items["Content"]
            end

            local Items = {}
            do
                Items["Dropdown"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Parent.Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 40),
                    BorderSizePixel = 0
                })

                Items["Dropdown"]:Tooltip(Dropdown.Tooltip)

                Items["RealDropdown"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Dropdown"].Instance,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 0, 1, 0),
                    Size = UDim2.new(1, 0, 0, 20),
                    ClipsDescendants = true,
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RealDropdown"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RealDropdown"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = Items["RealDropdown"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                Items["Value"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["RealDropdown"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = "...",
                    AnchorPoint = Vector2.new(0, 0.5),
                    Size = UDim2.new(1, -24, 0, 15),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 8, 0.5, -1),
                    BorderSizePixel = 0,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["Icon"] = Library:Create("ImageLabel", {
                    Name = "\0",
                    Parent = Items["RealDropdown"].Instance,
                    ImageColor3 = Library.Theme["Text"],
                    AnchorPoint = Vector2.new(1, 0.5),
                    Image = "rbxassetid://88550711858254",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -4, 0.5, 0),
                    Size = UDim2.new(0, 14, 0, 14),
                    BorderSizePixel = 0
                }):AddToTheme({ ImageColor3 = 'Text' })

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Dropdown"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Dropdown.Name,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 12),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["OptionHolder"] = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Library.UnusedHolder.Instance,
                    Visible = false,
                    TextColor3 = Color3.fromRGB(0, 0, 0),
                    Text = "",
                    AutoButtonColor = false,
                    Size = UDim2.new(0, 210, 0, 50),
                    Position = UDim2.new(0, 1056, 0, 521),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Library.Theme["Background"]
                }):AddToTheme({ BackgroundColor3 = 'Background' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["OptionHolder"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["OptionHolder"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["OptionHolder"].Instance,
                    Padding = UDim.new(0, 3),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["OptionHolder"].Instance,
                    PaddingTop = UDim.new(0, 4),
                    PaddingLeft = UDim.new(0, 8),
                    PaddingBottom = UDim.new(0, 6)
                })

                Items["RealDropdown"]:OnHover(function()
                    Items["RealDropdown"]:Tween({ BackgroundColor3 = Library.Theme["Hovered Element"] })
                end, function()
                    Items["RealDropdown"]:Tween({ BackgroundColor3 = Library.Theme["Element"] })
                end)

                Dropdown.Items = Items
            end

            function Dropdown:Set(Value)
                if Dropdown.Multi then
                    if type(Value) ~= "table" then
                        return
                    end

                    Dropdown.Value = Value

                    for Index, Value in Value do
                        local OptionData = Dropdown.Options[Value]

                        if not OptionData then
                            continue
                        end

                        OptionData.IsSelected = true
                        OptionData:ToggleState("Active")
                    end

                    Flags[Dropdown.Flag] = Value
                    Items["Value"].Instance.Text = table.concat(Value, ", ")
                else
                    if not Dropdown.Options[Value] then
                        return
                    end

                    local OptionData = Dropdown.Options[Value]

                    Dropdown.Value = Value

                    for Index, Value in Dropdown.Options do
                        if Value ~= OptionData then
                            Value.IsSelected = false
                            Value:ToggleState("Inactive")
                        else
                            Value.Selected = true
                            Value:ToggleState("Active")
                        end
                    end

                    Flags[Dropdown.Flag] = Value
                    Items["Value"].Instance.Text = Value
                end

                Library:SafeCall(Dropdown.Callback, Dropdown.Value)
            end

            function Dropdown:Add(Value)
                local OptionButton = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["OptionHolder"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Value,
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 15),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                local OptionData = {
                    Button = OptionButton,
                    Name = Value,
                    IsSelected = false
                }

                function OptionData:ToggleState(Value)
                    if Value == "Active" then
                        OptionData.Button:ChangeItemTheme({ TextColor3 = "Accent" })
                        OptionData.Button:Tween({ TextColor3 = Library.Theme.Accent })
                    else
                        OptionData.Button:ChangeItemTheme({ TextColor3 = "Text" })
                        OptionData.Button:Tween({ TextColor3 = Library.Theme.Text })
                    end
                end

                function OptionData:Set()
                    OptionData.IsSelected = not OptionData.IsSelected

                    if Dropdown.Multi then
                        local Index = table.find(Dropdown.Value, OptionData.Name)

                        if Index then
                            table.remove(Dropdown.Value, Index)
                        else
                            table.insert(Dropdown.Value, OptionData.Name)
                        end

                        OptionData:ToggleState(Index and "Inactive" or "Active")

                        Flags[Dropdown.Flag] = Dropdown.Value

                        local TextFormat = #Dropdown.Value > 0 and table.concat(Dropdown.Value, ", ") or ""
                        Items["Value"].Instance.Text = TextFormat
                    else
                        if OptionData.IsSelected then
                            Dropdown.Value = OptionData.Name
                            Flags[Dropdown.Flag] = OptionData.Name

                            OptionData.IsSelected = true
                            OptionData:ToggleState("Active")

                            for Index, Value in Dropdown.Options do
                                if Value ~= OptionData then
                                    Value.IsSelected = false
                                    Value:ToggleState("Inactive")
                                end
                            end

                            Items["Value"].Instance.Text = OptionData.Name
                        else
                            Dropdown.Value = nil
                            Flags[Dropdown.Flag] = nil

                            OptionData.IsSelected = false
                            OptionData:ToggleState("Inactive")

                            Items["Value"].Instance.Text = "..."
                        end
                    end

                    Library:SafeCall(Dropdown.Callback, Dropdown.Value)
                end

                OptionData.Button:Connect("MouseButton1Down", function()
                    OptionData:Set()
                end)

                Dropdown.Options[OptionData.Name] = OptionData
                return OptionData
            end

            function Dropdown:Remove(Option)
                if Dropdown.Options[Option] then
                    Dropdown.Options[Option].Button.Instance:Destroy()
                    Dropdown.Options[Option] = nil
                end
            end

            function Dropdown:Refresh(List)
                for Index, Value in Dropdown.Options do
                    Dropdown:Remove(Value.Name)
                end

                for Index, Value in List do
                    Dropdown:Add(Value)
                end
            end

            function Dropdown:SetText(Text)
                Items["Text"].Instance.Text = tostring(Text)
            end

            function Dropdown:SetVisibility(Bool)
                Items["Dropdown"].Instance.Visible = Bool
            end

            local Debounce = false
            local RenderStepped
            local OptionHolder = Items["OptionHolder"].Instance
            local RealDropdown = Items["RealDropdown"].Instance

            Dropdown.AttachedButton = RealDropdown
            Dropdown.CanUpdateNow = false
            Dropdown.Frame = OptionHolder

            function Dropdown:SetOpen(Bool)
                if Debounce then
                    return
                end

                Dropdown.IsOpen = Bool

                Debounce = true

                if Dropdown.IsOpen then
                    Items["Icon"]:Tween({ Rotation = -90 })
                    OptionHolder.Position = UDim2.new(0, RealDropdown.AbsolutePosition.X, 0,
                        RealDropdown.AbsolutePosition.Y + RealDropdown.AbsoluteSize.Y + GuiInset)
                    OptionHolder.Size = UDim2.new(0, RealDropdown.AbsoluteSize.X, 0, Dropdown.MaxSize)

                    OptionHolder.Parent = Library.Holder.Instance
                    OptionHolder.Visible = true
                    Items["OptionHolder"]:Tween({
                        Position = UDim2.new(0, RealDropdown.AbsolutePosition.X, 0,
                            RealDropdown.AbsolutePosition.Y + RealDropdown.AbsoluteSize.Y + 10 + GuiInset)
                    })

                    Items["OptionHolder"]:FadeDescendants(true, function()
                        Debounce = false
                        Dropdown.CanUpdateNow = true
                    end)

                    for Index, Value in Library.OpenFrames do
                        if not Params.Parent and not Dropdown.Section.IsSettings then
                            Value:SetOpen(false)
                        end
                    end

                    Library.OpenFrames[Dropdown] = Dropdown
                else
                    Items["Icon"]:Tween({ Rotation = 0 })
                    Items["OptionHolder"]:Tween({
                        Position = UDim2.new(0, RealDropdown.AbsolutePosition.X, 0,
                            RealDropdown.AbsolutePosition.Y + RealDropdown.AbsoluteSize.Y - 10 + GuiInset)
                    })
                    Items["OptionHolder"]:FadeDescendants(false, function()
                        OptionHolder.Parent = Library.UnusedHolder.Instance
                        Debounce = false
                        Dropdown.CanUpdateNow = false
                    end)

                    if Library.OpenFrames[Dropdown] then
                        Library.OpenFrames[Dropdown] = nil
                    end

                    if RenderStepped then
                        RenderStepped:Disconnect()
                        RenderStepped = nil
                    end
                end

                local Descendants = OptionHolder:GetDescendants()
                table.insert(Descendants, OptionHolder)

                for Index, Value in Descendants do
                    if Value.ClassName:find("UI") then
                        continue
                    end

                    if not Params.Parent then
                        Value.ZIndex = Dropdown.IsOpen and 3 or 1
                    else
                        Value.ZIndex = Dropdown.IsOpen and 6 or 1
                    end
                end
            end

            Items["RealDropdown"]:Connect("MouseButton1Down", function()
                Dropdown:SetOpen(not Dropdown.IsOpen)
            end)

            Library:Connect(UserInputService.InputBegan, function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                    if Dropdown.IsOpen then
                        if Items["OptionHolder"]:IsMouseOverFrame() then
                            return
                        end

                        Dropdown:SetOpen(false)
                    end
                end
            end)

            Items["RealDropdown"]:Connect("Changed", function(Property)
                if Property == "AbsolutePosition" and Dropdown.IsOpen then
                    local Section = Dropdown.Section
                    local SectionItem = Section and Section.Items and Section.Items["Section"]
                    local SectionInstance = SectionItem and SectionItem.Instance
                    local SectionParent = SectionInstance and SectionInstance.Parent

                    if SectionParent then
                        Dropdown.IsOpen = not Items["OptionHolder"]:IsClipped(SectionParent)
                    else
                        Dropdown.IsOpen = false
                    end
                    Items["OptionHolder"].Instance.Visible = Dropdown.IsOpen
                end
            end)

            for Index, Value in Dropdown.OptionItems do
                Dropdown:Add(Value)
            end

            Dropdown:Set(Dropdown.Default)

            SetFlags[Dropdown.Flag] = function(Value)
                Dropdown:Set(Value)
            end

            return setmetatable(Dropdown, Library)
        end

        Library.Label = function(Self, Params)
            Params = Params or {}

            local Label = {
                Name = Params.Name or Params.name or "Label",
                Tooltip = Params.Tooltip or Params.tooltip or nil,

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,

                Items = {}
            }

            local Items = {}
            do
                Items["Label"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Label.Section.Items["Content"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 12),
                    BorderSizePixel = 0
                })

                Items["Label"]:Tooltip(Label.Tooltip)

                Items["Text"] = Library:Create("TextLabel", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Label"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Label.Name,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Size = UDim2.new(0, 0, 0, 12),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 0, 0.5, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                Items["SubElements"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Label"].Instance,
                    AnchorPoint = Vector2.new(1, 0),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, 0, 0, 0),
                    Size = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["SubElements"].Instance,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalAlignment = Enum.HorizontalAlignment.Right,
                    Padding = UDim.new(0, 6),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Label.Items = Items
            end

            function Label:SetVisibility(Bool)
                Items["Label"].Instance.Visible = Bool
            end

            function Label:SetText(Text)
                Items["Text"].Instance.Text = tostring(Text)
            end

            function Label:Colorpicker(Data)
                Data = Data or {}

                local Colorpicker = {
                    Flag = Data.Flag or Data.flag or (Data.Name or Data.name or Label.Name),
                    Default = Data.Default or Data.default or Color3.fromRGB(255, 255, 255),
                    Callback = Data.Callback or Data.callback or function() end,
                    Alpha = Data.Alpha or Data.alpha or 0,

                    Window = Label.Window,
                    Page = Label.Page,
                    Section = Label.Section,
                }

                local NewColorpicker, ColorpickerItems = Library:CreateColorpicker({
                    Parent = Items["SubElements"],
                    Page = Colorpicker.Page,
                    Section = Colorpicker.Section,
                    Flag = Colorpicker.Flag,
                    Default = Colorpicker.Default,
                    Callback = Colorpicker.Callback,
                    Alpha = Colorpicker.Alpha
                })

                return NewColorpicker
            end

            function Label:Keybind(Data)
                Data = Data or {}

                local Keybind = {
                    Name = Data.Name or Data.name or Label.Name,
                    Flag = Data.Flag or Data.flag or (Data.Name or Data.name or Label.Name),
                    Default = Data.Default or Data.default,
                    Callback = Data.Callback or Data.callback or function() end,
                    Mode = Data.Mode or Data.mode or "Toggle",

                    Window = Label.Window,
                    Page = Label.Page,
                    Section = Label.Section,
                }

                local NewKeybind, KeybindItems = Library:CreateKeybind({
                    Parent = Items["SubElements"],
                    Name = Keybind.Name,
                    Page = Keybind.Page,
                    Section = Keybind.Section,
                    Flag = Keybind.Flag,
                    Default = Keybind.Default,
                    Mode = Keybind.Mode,
                    Callback = Keybind.Callback
                })

                return NewKeybind
            end

            Label:SetText(Label.Name)

            return setmetatable(Label, Library)
        end

        Library.Textbox = function(Self, Params)
            Params = Params or {}

            local Textbox = {
                Name = Params.Name or Params.name or "Textbox",
                Flag = Params.Flag or Params.flag or (Params.Name or Params.name),
                Default = Params.Default or Params.default or "",
                Callback = Params.Callback or Params.callback or function() end,
                Tooltip = Params.Tooltip or Params.tooltip or nil,
                Finished = Params.Finished or Params.finished or false,
                Numeric = Params.Numeric or Params.numeric or false,
                Placeholder = Params.Placeholder or Params.placeholder or "...",

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,
                Value = "",

                Items = {},
            }

            local Items = {}
            do
                Items["Textbox"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Textbox.Section.Items["Content"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 20),
                    BorderSizePixel = 0
                })

                Items["Textbox"]:Tooltip(Textbox.Tooltip)

                Items["Background"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Textbox"].Instance,
                    ClipsDescendants = true,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["Background"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, -1)
                }):AddToTheme({ Color = 'Border' })

                Items["Input"] = Library:Create("TextBox", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Background"].Instance,
                    AnchorPoint = Vector2.new(0, 0.5),
                    PlaceholderColor3 = Library.Theme["Inactive Text"],
                    PlaceholderText = Textbox.Placeholder,
                    Size = UDim2.new(1, -16, 0, 15),
                    TextColor3 = Library.Theme["Text"],
                    Text = "",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 8, 0.5, -1),
                    ClearTextOnFocus = false,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = 'Text' })

                Textbox.Items = Items
            end

            function Textbox:SetVisibility(Bool)
                Items["Textbox"].Instance.Visible = Bool
            end

            function Textbox:SetText(Text)
                Items["Text"].Instance.Text = tostring(Text)
            end

            function Textbox:Set(Value)
                if Textbox.Numeric then
                    if (not tonumber(Value)) and string.len(tostring(Value)) > 0 then
                        Value = Textbox.Value
                    end
                end

                Textbox.Value = Value
                Items["Input"].Instance.Text = Value
                Flags[Textbox.Flag] = Value

                Library:SafeCall(Textbox.Callback, Value)
            end

            if Textbox.Finished then
                Items["Input"]:Connect("FocusLost", function(PressedEnterQuestionMark)
                    if PressedEnterQuestionMark then
                        Textbox:Set(Items["Input"].Instance.Text)
                    end
                end)
            else
                Library:Connect(Items["Input"].Instance:GetPropertyChangedSignal("Text"), function()
                    Textbox:Set(Items["Input"].Instance.Text)
                end)
            end

            Textbox:Set(Textbox.Default)

            SetFlags[Textbox.Flag] = function(Value)
                Textbox:Set(Value)
            end

            return setmetatable(Textbox, Library)
        end

        Library.Searchbox = function(Self, Params) -- just the dropdown func with diff items
            Params = Params or {}

            local Dropdown = {
                OptionItems = Params.Items or Params.items or {},
                Tooltip = Params.Tooltip or Params.tooltip or nil,
                Flag = Params.Flag or Params.flag or (Params.Name or Params.name),
                Default = Params.Default or Params.default or "",
                Callback = Params.Callback or Params.callback or function() end,
                Multi = Params.Multi or Params.multi or false,

                Window = Self.Window,
                Page = Self.Page,
                Section = Self,

                Value = {},
                Options = {},
                Items = {}
            }

            local Items = {}
            do
                Items["Searchbox"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Dropdown.Section.Items["Content"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 173),
                    BorderSizePixel = 0
                })

                Items["Search"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Searchbox"].Instance,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 20),
                    BorderSizePixel = 0
                })

                Items["SearchBackground"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Search"].Instance,
                    ClipsDescendants = true,
                    Size = UDim2.new(1, 0, 1, 0),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["SearchBackground"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, -1)
                }):AddToTheme({ Color = 'Border' })

                Items["Input"] = Library:Create("TextBox", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["SearchBackground"].Instance,
                    AnchorPoint = Vector2.new(0, 0.5),
                    PlaceholderColor3 = Library.Theme["Inactive Text"],
                    PlaceholderText = "Search",
                    Size = UDim2.new(1, -16, 0, 15),
                    TextColor3 = Library.Theme["Text"],
                    Text = "",
                    BackgroundTransparency = 1,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 8, 0.5, 0),
                    ClearTextOnFocus = false,
                    BorderSizePixel = 0
                }):AddToTheme({ TextColor3 = 'Text', PlaceholderColor3 = 'Inactive Text' })

                Items["RealSearchbox"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Searchbox"].Instance,
                    Position = UDim2.new(0, 0, 0, 25),
                    Size = UDim2.new(1, 0, 1, -25),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme["Element"]
                }):AddToTheme({ BackgroundColor3 = 'Element' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RealSearchbox"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = 'Border' })

                Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = Items["RealSearchbox"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = 'Outline' })

                Items["Holder"] = Library:Create("ScrollingFrame", {
                    Name = "\0",
                    Parent = Items["RealSearchbox"].Instance,
                    Active = true,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    BorderSizePixel = 0,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ScrollBarImageColor3 = Library.Theme["Accent"],
                    MidImage = "rbxassetid://129030709932941",
                    ScrollBarThickness = 1,
                    Size = UDim2.new(1, -8, 1, -8),
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 4, 0, 4),
                    BottomImage = "rbxassetid://129030709932941",
                    TopImage = "rbxassetid://129030709932941"
                }):AddToTheme({ ScrollBarImageColor3 = 'Accent' })

                Library:Create("UIListLayout", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    Padding = UDim.new(0, 3),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                Library:Create("UIPadding", {
                    Name = "\0",
                    Parent = Items["Holder"].Instance,
                    PaddingBottom = UDim.new(0, 6),
                    PaddingLeft = UDim.new(0, 6)
                })

                Dropdown.Items = Items
            end

            function Dropdown:Set(Value)
                if Dropdown.Multi then
                    if type(Value) ~= "table" then
                        return
                    end

                    Dropdown.Value = Value

                    for Index, Value in Value do
                        local OptionData = Dropdown.Options[Value]

                        if not OptionData then
                            continue
                        end

                        OptionData.IsSelected = true
                        OptionData:ToggleState("Active")
                    end

                    Flags[Dropdown.Flag] = Value
                else
                    if not Dropdown.Options[Value] then
                        return
                    end

                    local OptionData = Dropdown.Options[Value]

                    Dropdown.Value = Value

                    for Index, Value in Dropdown.Options do
                        if Value ~= OptionData then
                            Value.IsSelected = false
                            Value:ToggleState("Inactive")
                        else
                            Value.Selected = true
                            Value:ToggleState("Active")
                        end
                    end

                    Flags[Dropdown.Flag] = Value
                end

                Library:SafeCall(Dropdown.Callback, Dropdown.Value)
            end

            function Dropdown:Add(Value)
                local OptionButton = Library:Create("TextButton", {
                    Name = "\0",
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    Parent = Items["Holder"].Instance,
                    TextColor3 = Library.Theme["Text"],
                    Text = Value,
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 0, 15),
                    BorderSizePixel = 0,
                    AutomaticSize = Enum.AutomaticSize.X
                }):AddToTheme({ TextColor3 = 'Text' })

                local OptionData = {
                    Button = OptionButton,
                    Name = Value,
                    IsSelected = false
                }

                function OptionData:ToggleState(Value)
                    if Value == "Active" then
                        OptionData.Button:ChangeItemTheme({ TextColor3 = "Accent" })
                        OptionData.Button:Tween({ TextColor3 = Library.Theme.Accent })
                    else
                        OptionData.Button:ChangeItemTheme({ TextColor3 = "Text" })
                        OptionData.Button:Tween({ TextColor3 = Library.Theme.Text })
                    end
                end

                function OptionData:Set()
                    OptionData.IsSelected = not OptionData.IsSelected

                    if Dropdown.Multi then
                        local Index = table.find(Dropdown.Value, OptionData.Name)

                        if Index then
                            table.remove(Dropdown.Value, Index)
                        else
                            table.insert(Dropdown.Value, OptionData.Name)
                        end

                        OptionData:ToggleState(Index and "Inactive" or "Active")

                        Flags[Dropdown.Flag] = Dropdown.Value
                    else
                        if OptionData.IsSelected then
                            Dropdown.Value = OptionData.Name
                            Flags[Dropdown.Flag] = OptionData.Name

                            OptionData.IsSelected = true
                            OptionData:ToggleState("Active")

                            for Index, Value in Dropdown.Options do
                                if Value ~= OptionData then
                                    Value.IsSelected = false
                                    Value:ToggleState("Inactive")
                                end
                            end
                        else
                            Dropdown.Value = nil
                            Flags[Dropdown.Flag] = nil

                            OptionData.IsSelected = false
                            OptionData:ToggleState("Inactive")
                        end
                    end

                    Library:SafeCall(Dropdown.Callback, Dropdown.Value)
                end

                OptionData.Button:Connect("MouseButton1Down", function()
                    OptionData:Set()
                end)

                Dropdown.Options[OptionData.Name] = OptionData
                return OptionData
            end

            function Dropdown:Remove(Option)
                if Dropdown.Options[Option] then
                    Dropdown.Options[Option].Button.Instance:Destroy()
                    Dropdown.Options[Option] = nil
                end
            end

            function Dropdown:Refresh(List)
                for Index, Value in Dropdown.Options do
                    Dropdown:Remove(Value.Name)
                end

                for Index, Value in List do
                    Dropdown:Add(Value)
                end
            end

            function Dropdown:SetVisibility(Bool)
                Items["Searchbox"].Instance.Visible = Bool
            end

            Library:Connect(Items["Input"].Instance:GetPropertyChangedSignal("Text"), function()
                for Index, Value in Dropdown.Options do
                    if string.lower(Value.Name):find(string.lower(Items["Input"].Instance.Text)) then
                        Value.Button.Instance.Visible = true
                    else
                        Value.Button.Instance.Visible = false
                    end
                end
            end)

            for Index, Value in Dropdown.OptionItems do
                Dropdown:Add(Value)
            end

            Dropdown:Set(Dropdown.Default)

            SetFlags[Dropdown.Flag] = function(Value)
                Dropdown:Set(Value)
            end

            return setmetatable(Dropdown, Library)
        end

        Library.OpenConfirmDialog = function(Self, Config)
            Config = Config or {}

            local Title = tostring(Config.Title or "Confirm")
            local Message = tostring(Config.Message or "Are you sure you want to continue?")
            local ConfirmText = tostring(Config.ConfirmText or "Confirm")
            local CancelText = tostring(Config.CancelText or "Cancel")
            local AccentColor = Config.AccentColor or Color3.fromRGB(255, 95, 95)
            local Callback = Config.Callback or function() end

            if Self.ActiveConfirmDialog and Self.ActiveConfirmDialog.Close then
                Self.ActiveConfirmDialog:Close(false, true)
            end

            local Items = {}
            local Connections = {}
            local IsClosed = false

            local function AddConnection(Connection)
                table.insert(Connections, Connection)
                return Connection
            end

            local function DisconnectConnections()
                for _, Connection in Connections do
                    if Connection and Connection.Connected then
                        Connection:Disconnect()
                    end
                end
            end

            local function CreateModalButton(Name, Position, Width, TextColor, BackgroundTheme)
                local ButtonItems = {}

                ButtonItems["Button"] = Library:Create("TextButton", {
                    Name = "\0",
                    Parent = Items["Panel"].Instance,
                    Position = Position,
                    Size = UDim2.new(Width, 0, 0, 18),
                    BorderSizePixel = 0,
                    BackgroundColor3 = Library.Theme[BackgroundTheme]
                }):AddToTheme({ BackgroundColor3 = BackgroundTheme })

                ButtonItems["OuterStroke"] = Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = ButtonItems["Button"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Border"],
                    BorderOffset = UDim.new(0, 1)
                }):AddToTheme({ Color = "Border" })

                ButtonItems["InnerStroke"] = Library:Create("UIStroke", {
                    Name = "\0",
                    Parent = ButtonItems["Button"].Instance,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                    Color = Library.Theme["Outline"]
                }):AddToTheme({ Color = "Outline" })

                Library:Create("UIGradient", {
                    Name = "\0",
                    Parent = ButtonItems["Button"].Instance,
                    Rotation = -90,
                    Color = ColorSequence.new {
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172))
                    }
                })

                ButtonItems["Label"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = ButtonItems["Button"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.5, 0, 0.5, -1),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Size = UDim2.new(0, 0, 0, 15),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BorderSizePixel = 0,
                    Text = Name,
                    TextColor3 = TextColor,
                    FontFace = Library.Font,
                    TextSize = Library.FontSize
                })

                ButtonItems["Button"]:OnHover(function()
                    ButtonItems["Button"]:Tween({ BackgroundColor3 = Library.Theme["Hovered Element"] })
                end, function()
                    ButtonItems["Button"]:Tween({ BackgroundColor3 = Library.Theme[BackgroundTheme] })
                end)

                return ButtonItems
            end

            do
                Items["Overlay"] = Library:Create("TextButton", {
                    Name = "\0",
                    Parent = Self.Holder.Instance,
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = Color3.new(0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    ZIndex = 9000
                })

                Items["PanelOutline"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Overlay"].Instance,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 10),
                    Size = UDim2.new(0, 264, 0, 124),
                    BackgroundColor3 = Library.Theme["Outline"],
                    BorderSizePixel = 0,
                    ZIndex = 9001
                }):AddToTheme({ BackgroundColor3 = "Outline" })

                Items["PanelScale"] = Library:Create("UIScale", {
                    Name = "\0",
                    Parent = Items["PanelOutline"].Instance,
                    Scale = 0.94
                })

                Items["Panel"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["PanelOutline"].Instance,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    BackgroundColor3 = Library.Theme["Section"],
                    BorderSizePixel = 0,
                    ZIndex = 9002
                }):AddToTheme({ BackgroundColor3 = "Section" })

                Items["AccentLine"] = Library:Create("Frame", {
                    Name = "\0",
                    Parent = Items["Panel"].Instance,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    BackgroundColor3 = AccentColor,
                    ZIndex = 9003
                })

                Items["Title"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = Items["Panel"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 12, 0, 10),
                    Size = UDim2.new(1, -24, 0, 12),
                    BorderSizePixel = 0,
                    Text = Title,
                    TextColor3 = Library.Theme["Text"],
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 9003
                }):AddToTheme({ TextColor3 = "Text" })

                Items["Message"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = Items["Panel"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 12, 0, 29),
                    Size = UDim2.new(1, -24, 0, 50),
                    BorderSizePixel = 0,
                    Text = Message,
                    TextColor3 = Library.Theme["Text"],
                    TextTransparency = 0.25,
                    TextWrapped = true,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    ZIndex = 9003
                }):AddToTheme({
                    TextColor3 = function()
                        return Library.Theme["Text"]:Lerp(Color3.new(0, 0, 0), 0.25)
                    end
                })

                Items["Hint"] = Library:Create("TextLabel", {
                    Name = "\0",
                    Parent = Items["Panel"].Instance,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 12, 1, -49),
                    Size = UDim2.new(1, -24, 0, 10),
                    BorderSizePixel = 0,
                    Text = "Click off this window to cancel\nHit enter to confirm",
                    TextColor3 = Library.Theme["Text"],
                    TextTransparency = 0.45,
                    FontFace = Library.Font,
                    TextSize = Library.FontSize,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 9003
                }):AddToTheme({
                    TextColor3 = function()
                        return Library.Theme["Text"]:Lerp(Color3.new(0, 0, 0), 0.45)
                    end
                })

                Items["CancelButton"] = CreateModalButton(CancelText, UDim2.new(0, 12, 1, -30), 0.45,
                    Library.Theme["Text"], "Element")
                Items["ConfirmButton"] = CreateModalButton(ConfirmText, UDim2.new(0.55, 0, 1, -30), 0.45,
                    AccentColor, "Element")
            end

            local FadeItems = {
                Items["Overlay"],
                Items["PanelOutline"],
                Items["Panel"],
                Items["AccentLine"],
                Items["Title"],
                Items["Message"],
                Items["Hint"],
                Items["CancelButton"]["OuterStroke"],
                Items["CancelButton"]["InnerStroke"],
                Items["CancelButton"]["Label"],
                Items["CancelButton"]["Button"],
                Items["ConfirmButton"]["OuterStroke"],
                Items["ConfirmButton"]["InnerStroke"],
                Items["ConfirmButton"]["Label"],
                Items["ConfirmButton"]["Button"]
            }

            for _, Item in FadeItems do
                if Item.Instance:IsA("Frame") then
                    Item.Instance.BackgroundTransparency = 1
                elseif Item.Instance:IsA("TextLabel") then
                    Item.Instance.TextTransparency = 1
                elseif Item.Instance:IsA("UIStroke") then
                    Item.Instance.Transparency = 1
                elseif Item.Instance:IsA("TextButton") then
                    Item.Instance.BackgroundTransparency = 1
                end
            end

            local OpenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            local CloseInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

            local Dialog = {}

            function Dialog:Close(Confirmed, SkipCallback)
                if IsClosed then
                    return
                end

                IsClosed = true
                Self.ActiveConfirmDialog = nil

                Items["Overlay"]:Tween({ BackgroundTransparency = 1 }, CloseInfo)
                Items["PanelOutline"]:Tween({ BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 6) },
                    CloseInfo)
                Items["Panel"]:Tween({ BackgroundTransparency = 1 }, CloseInfo)
                Items["AccentLine"]:Tween({ BackgroundTransparency = 1 }, CloseInfo)
                Items["Title"]:Tween({ TextTransparency = 1 }, CloseInfo)
                Items["Message"]:Tween({ TextTransparency = 1 }, CloseInfo)
                Items["Hint"]:Tween({ TextTransparency = 1 }, CloseInfo)
                Items["CancelButton"]["Button"]:Tween({ BackgroundTransparency = 1 }, CloseInfo)
                Items["CancelButton"]["OuterStroke"]:Tween({ Transparency = 1 }, CloseInfo)
                Items["CancelButton"]["InnerStroke"]:Tween({ Transparency = 1 }, CloseInfo)
                Items["CancelButton"]["Label"]:Tween({ TextTransparency = 1 }, CloseInfo)
                Items["ConfirmButton"]["Button"]:Tween({ BackgroundTransparency = 1 }, CloseInfo)
                Items["ConfirmButton"]["OuterStroke"]:Tween({ Transparency = 1 }, CloseInfo)
                Items["ConfirmButton"]["InnerStroke"]:Tween({ Transparency = 1 }, CloseInfo)
                Items["ConfirmButton"]["Label"]:Tween({ TextTransparency = 1 }, CloseInfo)
                Items["PanelScale"]:Tween({ Scale = 0.97 }, CloseInfo)

                task.delay(CloseInfo.Time + 0.03, function()
                    DisconnectConnections()

                    if Items["Overlay"] and Items["Overlay"].Instance.Parent then
                        Items["Overlay"].Instance:Destroy()
                    end
                end)

                if not SkipCallback then
                    task.defer(function()
                        Library:SafeCall(Callback, Confirmed)
                    end)
                end
            end

            Self.ActiveConfirmDialog = Dialog

            Items["Overlay"]:Tween({ BackgroundTransparency = 0.35 }, OpenInfo)
            Items["PanelOutline"]:Tween({ BackgroundTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0) }, OpenInfo)
            Items["Panel"]:Tween({ BackgroundTransparency = 0 }, OpenInfo)
            Items["AccentLine"]:Tween({ BackgroundTransparency = 0 }, OpenInfo)
            Items["Title"]:Tween({ TextTransparency = 0 }, OpenInfo)
            Items["Message"]:Tween({ TextTransparency = 0.25 }, OpenInfo)
            Items["Hint"]:Tween({ TextTransparency = 0.45 }, OpenInfo)
            Items["CancelButton"]["Button"]:Tween({ BackgroundTransparency = 0 }, OpenInfo)
            Items["CancelButton"]["OuterStroke"]:Tween({ Transparency = 0 }, OpenInfo)
            Items["CancelButton"]["InnerStroke"]:Tween({ Transparency = 0 }, OpenInfo)
            Items["CancelButton"]["Label"]:Tween({ TextTransparency = 0 }, OpenInfo)
            Items["ConfirmButton"]["Button"]:Tween({ BackgroundTransparency = 0 }, OpenInfo)
            Items["ConfirmButton"]["OuterStroke"]:Tween({ Transparency = 0 }, OpenInfo)
            Items["ConfirmButton"]["InnerStroke"]:Tween({ Transparency = 0 }, OpenInfo)
            Items["ConfirmButton"]["Label"]:Tween({ TextTransparency = 0 }, OpenInfo)
            Items["PanelScale"]:Tween({ Scale = 1 }, OpenInfo)

            AddConnection(Items["Overlay"].Instance.MouseButton1Click:Connect(function()
                Dialog:Close(false)
            end))

            AddConnection(Items["CancelButton"]["Button"].Instance.MouseButton1Click:Connect(function()
                Dialog:Close(false)
            end))

            AddConnection(Items["ConfirmButton"]["Button"].Instance.MouseButton1Click:Connect(function()
                Dialog:Close(true)
            end))

            AddConnection(UserInputService.InputBegan:Connect(function(Input, Processed)
                if Processed or IsClosed then
                    return
                end

                if Input.KeyCode == Enum.KeyCode.Escape then
                    Dialog:Close(false)
                elseif Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.KeypadEnter then
                    Dialog:Close(true)
                end
            end))

            return Dialog
        end

        Library.CreateSettingsPage = function(Self)
            local Page = Self:Page({ Name = "Settings", Icon = "rbxassetid://0" })

            local ConfigsSubPage = Page:SubPage({ Name = "Configs" })
            local OtherSubPage = Page:SubPage({ Name = "Other" })

            do
                local ConfigName
                local ConfigSelected
                local ConfigsFolder = Library.Directory .. Library.Folders.Configs .. "/"

                local ConfigsSection = ConfigsSubPage:Section({ Name = "Configs", Side = 1 })
                do
                    local ConfigName
                    local ConfigSelected
                    local ConfigsFolder = Library.Directory .. Library.Folders.Configs .. "/"

                    local ConfigsDropdown = ConfigsSection:Dropdown({
                        Name = "Configs",
                        Flag = "ConfigsDropdown",
                        Items = {},
                        Multi = false,
                        Callback = function(Value)
                            ConfigSelected = Value
                        end
                    })

                    ConfigsSection:Textbox({
                        Name = "Config name",
                        Flag = "ConfigName",
                        Placeholder = "Config name",
                        Callback = function(Value)
                            ConfigName = Value
                        end
                    })

                    ConfigsSection:Button({
                        Name = "Create",
                        Callback = function()
                            if ConfigName then
                                if ConfigName == "" then
                                    return
                                end

                                writefile(ConfigsFolder .. ConfigName .. ".json", Library:GetConfig())
                                Library:GetConfigsList(ConfigsDropdown)
                                Library:Notification("Succesfully created config", 3, Color3.fromRGB(0, 255, 0))
                            end
                        end
                    })

                    ConfigsSection:Button({
                        Name = "Delete",
                        Callback = function()
                            if ConfigSelected then
                                if isfile(ConfigsFolder .. ConfigSelected .. ".json") then
                                    local SelectedConfig = ConfigSelected

                                    Library:OpenConfirmDialog({
                                        Title = "Delete config",
                                        Message = string.format(
                                            'Delete "%s"? This permanently removes the file from your config folder.',
                                            SelectedConfig),
                                        ConfirmText = "Delete",
                                        CancelText = "Keep",
                                        AccentColor = Color3.fromRGB(255, 95, 95),
                                        Callback = function(Confirmed)
                                            if not Confirmed then
                                                return
                                            end

                                            if not isfile(ConfigsFolder .. SelectedConfig .. ".json") then
                                                Library:Notification("Config no longer exists", 3,
                                                    Color3.fromRGB(255, 0, 0))
                                                return
                                            end

                                            delfile(ConfigsFolder .. SelectedConfig .. ".json")
                                            ConfigSelected = nil
                                            Library:GetConfigsList(ConfigsDropdown)
                                            Library:Notification("Succesfully deleted config", 3,
                                                Color3.fromRGB(0, 255, 0))
                                        end
                                    })
                                end
                            end
                        end
                    })

                    ConfigsSection:Button({
                        Name = "Load",
                        Callback = function()
                            if ConfigSelected then
                                if isfile(ConfigsFolder .. ConfigSelected .. ".json") then
                                    local ConfigContent = readfile(ConfigsFolder .. ConfigSelected .. ".json")
                                    local Success, Error = Library:LoadConfig(ConfigContent)

                                    if Success then
                                        Library:Notification("Succesfully loaded config", 3, Color3.fromRGB(0, 255, 0))
                                    else
                                        Library:Notification("Failed to load config: \n" .. Error, 3,
                                            Color3.fromRGB(255, 0, 0))
                                    end
                                end
                            else
                                Library:Notification("No config selected", 3, Color3.fromRGB(255, 0, 0))
                            end
                        end
                    })

                    ConfigsSection:Button({
                        Name = "Save",
                        Callback = function()
                            if ConfigSelected then
                                if isfile(ConfigsFolder .. ConfigSelected .. ".json") then
                                    local Success, Error = pcall(function()
                                        writefile(ConfigsFolder .. ConfigSelected .. ".json", Library:GetConfig())
                                    end)

                                    if Success then
                                        Library:Notification("Succesfully saved config", 3, Color3.fromRGB(0, 255, 0))
                                    else
                                        Library:Notification("Failed to save config: \n" .. Error, 3,
                                            Color3.fromRGB(255, 0, 0))
                                    end
                                end
                            end
                        end
                    })

                    Library:GetConfigsList(ConfigsDropdown)
                end
            end

            do
                local ThemingSection = OtherSubPage:Section({ Name = "Theming", Side = 1 })
                do
                    for Index, Value in Library.Theme do
                        ThemingSection:Label({ Name = Index }):Colorpicker({
                            Flag = Index .. "Theme",
                            Default = Value,
                            Callback = function(Value)
                                Library.Theme[Index] = Value
                                Library:ChangeTheme(Index, Value)
                            end
                        })
                    end
                end

                local SettingsSection = OtherSubPage:Section({ Name = "Settings", Side = 2 })
                do
                    SettingsSection:Label({ Name = "UI Bind" }):Keybind({
                        Flag = "UIBind",
                        Mode = "Toggle",
                        Default = Enum.KeyCode.RightShift,
                        Callback = function(Value)
                            Library.MenuKeybind = Flags["UIBind"].Key
                        end
                    })

                    SettingsSection:Toggle({
                        Name = "Background Blur",
                        Flag = "UIBackgroundBlur",
                        Default = Library.BackgroundBlurEnabled,
                        Callback = function(Value)
                            Library:SetBackgroundBlurEnabled(Value)
                        end
                    })

                    SettingsSection:Toggle({
                        Name = "Background Snow",
                        Flag = "UIBackgroundSnow",
                        Default = Library.BackgroundSnowEnabled,
                        Callback = function(Value)
                            Library:SetBackgroundSnowEnabled(Value)
                        end
                    })

                    SettingsSection:Button({
                        Name = "Unload",
                        Callback = function()
                            Library:Exit()
                        end
                    })

                    SettingsSection:Slider({
                        Name = "Animation Speed",
                        Flag = "AnimationSpeed",
                        Default = Library.Animation.Time,
                        Min = 0,
                        Max = 1.5,
                        Decimals = .01,
                        Callback = function(Value)
                            Library.Animation.Time = Value
                        end
                    })
                end

                local WidgetsSection = OtherSubPage:Section({ Name = "Widgets", Side = 2 })
                do
                    for _, WidgetData in Library.SettingsWidgets do
                        local WidgetToggle = WidgetsSection:Toggle({
                            Name = WidgetData.Name,
                            Flag = WidgetData.Flag,
                            Default = WidgetData.Default,
                            Callback = WidgetData.Callback
                        })

                        if type(WidgetData.Settings) == "function" then
                            local WidgetSettings = WidgetToggle:Settings()
                            WidgetData.Settings(WidgetSettings, WidgetToggle)
                        end
                    end
                end
            end
        end
    end
end

_G.Library = Library
getgenv().Library = Library
return Library
