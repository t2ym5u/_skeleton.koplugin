local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase      = require("screen_base")
local MenuHelper      = require("menu_helper")
local SettingsDialog  = require("settings_dialog")

local MyGameBoard       = lrequire("board")
local MyGameBoardWidget = lrequire("board_widget")


-- ---------------------------------------------------------------------------
-- MyGameScreen
-- ---------------------------------------------------------------------------

local MyGameScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MyGameScreen:init()
    -- Load or create a board before calling ScreenBase:init (which calls buildLayout).
    local state = self.plugin:loadState()
    self.board = MyGameBoard:new()
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end
    ScreenBase.init(self)
end

function MyGameScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function MyGameScreen:buildLayout()
    local is_landscape = self:isLandscape()

    -- Title bar: the menu (left) holds everything that isn't played every
    -- turn -- new game, difficulty, settings, rules.
    local title_bar = self:buildTitleBar(_("My Game"), function()
        return {
            { text = _("New game"),                  callback = function() self:onNewGame() end },
            { text = self:getDifficultyButtonText(), callback = function() self:openDifficultyMenu() end },
            { text = _("Settings"),                  callback = function() self:openSettings() end },
        }
    end)

    -- Controls: status line, then the action bar, both at controls width.
    -- Use self:buildNumberPad(keys) for a digit/value pad, placed between them.
    local action_bar = self:buildActionBar({
        { id = "undo_button", text = _("Undo"),  callback = function() self:onUndo() end },
        { text = _("Check"),  callback = function() self:onCheck() end },
        { text = _("Reveal"), callback = function() self:onReveal() end },
    })
    self.undo_button = action_bar:getButtonById("undo_button")
    self:updateUndoButton()

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    -- The board takes whatever the title bar and the controls leave.
    local frame_pad = Size.padding.large
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = MyGameBoardWidget:new{
        board          = self.board,
        max_size       = math.min(budget_w, budget_h) - 2 * (frame_pad + Size.border.window),
        onCellSelected = function(row, col, is_hold)
            self:onCellSelected(row, col, is_hold)
        end,
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame, VerticalGroup:new{
            align = "center",
            controls,
            VerticalSpan:new{ width = self:getGutter() },
        })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function MyGameScreen:onCellSelected(row, col, is_hold)
    -- TODO: handle cell tap / long-press
    self:updateStatus(T(_("Cell %1,%2 selected."), row, col))
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function MyGameScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateUndoButton()
    self:updateStatus(_("New game started."))
end

function MyGameScreen:onUndo()
    -- TODO: implement undo using self.board.undo
    self:updateUndoButton()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Last move undone."))
end

function MyGameScreen:onCheck()
    -- TODO: validate current board state
    self:updateStatus(_("Checking…"))
end

function MyGameScreen:onReveal()
    -- TODO: show solution
    self:updateStatus(_("Solution revealed."))
    self.board_widget:refresh()
end

-- ---------------------------------------------------------------------------
-- Difficulty
-- ---------------------------------------------------------------------------

function MyGameScreen:getDifficultyButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

function MyGameScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDifficultyButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function MyGameScreen:openSettings()
    SettingsDialog.open{
        title  = _("My Game — Settings"),
        plugin = self.plugin,
        parent = self,
        sections = {
            {
                title = _("Gameplay"),
                items = {
                    {
                        label       = _("Difficulty"),
                        setting_key = "difficulty",
                        type        = "picker",
                        values      = {
                            { id = "easy",   text = _("Easy")   },
                            { id = "medium", text = _("Medium") },
                            { id = "hard",   text = _("Hard")   },
                        },
                        on_change = function(id)
                            self.plugin:saveSetting("difficulty", id)
                            if self.diff_button then
                                self.diff_button:setText(self:getDifficultyButtonText(), self.diff_button.width)
                            end
                        end,
                    },
                    -- Add more settings here, e.g.:
                    -- { label = _("Auto-save"), setting_key = "auto_save", type = "toggle" },
                },
            },
            {
                title = _("About"),
                items = {
                    { label = _("My Game v1.0"), type = "info" },
                },
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function MyGameScreen:updateStatus(message)
    local status
    if message then
        status = message
    else
        -- Status parts go through joinStatus so every game separates them
        -- the same way: size · difficulty · progress.
        local diff  = self.plugin:getSetting("difficulty", "easy")
        status = self:joinStatus(
            T("%1×%2", self.board.cols, self.board.rows),
            MenuHelper.DIFFICULTY_LABELS[diff] or diff)
        if self.board:isSolved() then
            status = _("Congratulations! Puzzle solved.")
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Button state helpers
-- ---------------------------------------------------------------------------

function MyGameScreen:updateUndoButton()
    if not self.undo_button then return end
    self.undo_button:enableDisable(self.board.undo:canUndo())
end

return MyGameScreen
