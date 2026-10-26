-- Draw stuff

local ui = {}

local LABEL_X, VALUE_X = 0, 24
local LABEL2_X, VALUE2_X = 62, 89
local ROW_Y = { 5, 12, 19, 26, 33, 40 }

-- 16 small heads below the param rows, one per column
local HEAD_X0, HEAD_DX = 34, 6
local HEAD_TOP, HEAD_BOT = 52, 63

-- six rows fit above the heads; E1 scrolls the rest into view
local VISIBLE = #ROW_Y

ui.ROWS = {
  { left = { "bpm:", "clock_tempo" }, right = { "sprd:", "spread" } },
  { left = { "curv:", "curve" },  right = { "phas:", "phase" } },
  { left = { "drft:", "drift" },  right = { "wndr:", "wander" } },
  { left = { "motn:", "motion" }, right = { "ordr:", "order" } },
  { left = { "bank:", "bank" },   right = { "wave:", "wave" } },
  { left = { "wspr:", "wave_spread" }, right = { "mrph:", "morph" } },
  { left = { "cutf:", "cutoff" }, right = { "fenv:", "env_cut" } },
  { left = { "atk:", "attack" },  right = { "dec:", "decay" } },
  { left = { "res:", "resonance" }, right = { "lvl:", "level" } },
  { left = { "clk:", "clock_source" }, right = { "pan:", "pan_spread" } },
}

local function secs(v)
  if v < 1 then return string.format("%dms", math.floor(v * 1000 + 0.5)) end
  return string.format("%.2fs", v)
end

local function signed(v)
  return string.format("%+.1f", v)
end

local RENDER = {
  -- the norns clock's own params; the tempo reads whatever the source sets
  clock_tempo = function() return string.format("%.0f", clock.get_tempo()) end,
  clock_source = function() return params:string("clock_source") end,
  spread = function(v) return string.format("%.2f%%", v) end,
  curve = function() return params:string("curve") end,
  phase = function(v) return string.format("%.2f", v) end,
  drift = function(v) return string.format("%+.3f", v) end,
  wander = function(v) return string.format("%.2f%%", v) end,
  motion = function() return params:string("motion") end,
  order = function() return params:string("order") end,
  bank = function(v) return ({ "a", "b", "c" })[v] or "?" end,
  wave = function(v) return string.format("%.1f", v) end,
  wave_spread = signed,
  morph = signed,
  cutoff = function(v)
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return string.format("%.0f", v)
  end,
  env_cut = signed,
  attack = secs,
  decay = secs,
  resonance = function(v) return string.format("%.2f", v) end,
  level = function(v) return string.format("%.2f", v) end,
  pan_spread = function(v) return string.format("%.2f", v) end,
}

function ui.row_count()
  return #ui.ROWS
end

-- live holds values that move on their own, shown in place of the param
local function draw_cell(lx, vx, y, label, id, lit, live)
  local v = live[id]
  if v == nil then v = params:get(id) end
  screen.level(2)
  screen.move(lx, y)
  screen.text(label)
  screen.level(lit and 15 or 5)
  screen.move(vx, y)
  screen.text(RENDER[id](v))
end

local top = 1

-- state: row, running, heights[i], flash[i], muted[i]
function ui.redraw(state)
  screen.aa(0)
  screen.line_width(1)
  screen.clear()

  if state.row < top then top = state.row end
  if state.row > top + VISIBLE - 1 then top = state.row - VISIBLE + 1 end

  local live = state.live or {}
  for k = 1, VISIBLE do
    local r = top + k - 1
    local row = ui.ROWS[r]
    if row == nil then break end
    local lit = r == state.row
    draw_cell(LABEL_X, VALUE_X, ROW_Y[k], row.left[1], row.left[2], lit, live)
    draw_cell(LABEL2_X, VALUE2_X, ROW_Y[k], row.right[1], row.right[2], lit, live)
  end

  -- a scroll mark when rows sit above or below the window
  screen.level(2)
  if top > 1 then screen.pixel(127, 1) end
  if top + VISIBLE - 1 < #ui.ROWS then screen.pixel(127, 41) end
  screen.fill()

  screen.level(state.running and 15 or 3)
  screen.move(LABEL_X, 62)
  screen.text(state.running and "run" or "stop")

  for i = 1, #state.heights do
    local x = HEAD_X0 + (i - 1) * HEAD_DX
    local y = HEAD_BOT - math.floor(state.heights[i] * (HEAD_BOT - HEAD_TOP) + 0.5)
    local lv = state.muted[i] and 2 or (5 + math.floor(state.flash[i] * 10))
    screen.level(lv)
    screen.rect(x, y - 1, 2, 2)
    screen.fill()
  end

  screen.update()
end

-- The play page: every column large enough to work on by hand.
local PLAY_X0, PLAY_DX = 4, 8
local PLAY_TOP, PLAY_BOT = 12, 52

-- state: col, held (K3 hold active), running, heights, flash, muted, note
function ui.redraw_play(state)
  screen.aa(0)
  screen.line_width(1)
  screen.clear()

  screen.level(15)
  screen.move(0, 6)
  screen.text("col " .. state.col)
  screen.level(5)
  screen.move(30, 6)
  screen.text(state.note or "")
  screen.level(state.muted[state.col] and 15 or 3)
  screen.move(56, 6)
  screen.text(state.muted[state.col] and "muted" or "on")
  screen.level(state.running and 15 or 3)
  screen.move(127, 6)
  screen.text_right(state.running and "run" or "stop")

  for i = 1, #state.heights do
    local x = PLAY_X0 + (i - 1) * PLAY_DX
    local sel = i == state.col

    -- the track each head swings along
    screen.level(sel and 3 or 1)
    screen.move(x + 0.5, PLAY_TOP)
    screen.line(x + 0.5, PLAY_BOT + 1)
    screen.stroke()

    local y = PLAY_BOT - math.floor(state.heights[i] * (PLAY_BOT - PLAY_TOP) + 0.5)
    local lv
    if sel and state.held then lv = 15
    elseif state.muted[i] then lv = 2
    else lv = 6 + math.floor(state.flash[i] * 9) end
    screen.level(lv)
    screen.rect(x - 1, y - 1, 3, 3)
    screen.fill()

    if sel then
      screen.level(15)
      screen.rect(x - 1, PLAY_BOT + 3, 3, 1)
      screen.fill()
    end
  end

  screen.level(3)
  screen.move(0, 63)
  if state.held then
    screen.text("E3:move head  top strikes")
  else
    -- 128px fits about 25 characters, so the hold lives in the README
    screen.text("E2:col E3:nudge K3:mute")
  end

  screen.update()
end

return ui
