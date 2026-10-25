--- talbot
-- v0.0.1 - @oootini
-- A 16 note pendulum arpeggiator
--
-- ▼ params page ▼
-- E1 - select row
-- E2 - edit left param
-- E3 - edit right param
-- K2 - to play page
-- K3 - run / stop
-- hold K3 - drop all heads
--
-- ▼ play page ▼
-- E2 - select column
-- E3 - nudge its head
-- K2 - to params page
-- K3 - mute / unmute
-- hold K3 + E3 - move the
--   head, top strikes
--
-- ▼ grid ▼
-- bottom row - mute column
-- rows above - hold the head
--   there, top row strikes
--
-- midi in - note sets root

engine.name = "Talbot"

MusicUtil = require "musicutil"

local swing = include "talbot/lib/swing"
local P = include "talbot/lib/params_def"
local ui = include "talbot/lib/ui"

local N = P.N
-- motion resolution; a ping lands at most one tick late
local TICK = 1 / 150
local FPS = 30
-- how fast a ping flash fades, per grid frame
local FLASH_DECAY = 0.82

local sw = swing.new(N)
local rates = {}
-- how far drift has carried the stagger past the phase param
local drift_acc = 0
-- wander's position in its cycle, 0 to 1, and the spread offset it gives
local wander_pos = 0
local wander_off = 0
local running = true
local row = 1
-- screen page: "params" or "play"
local page = "params"
-- column the play page works on
local col = 1
-- K3 hold: long enough to count as a hold, not a tap
local HOLD_TIME = 0.4
local k3_down, k3_held, k3_clock = false, false, nil
local flash = {}
local trail = {}

local g = grid.connect()
local grid_rows = 8

local midi_in = midi.connect()
local midi_out = nil
local midi_out_port = 0

local motion_clock, redraw_clock

for i = 1, N do
  flash[i] = 0
  trail[i] = {}
end

-- notes and pings ----------------------------------------------------

local function send_midi(i)
  local port = params:get("midi_out") - 1
  if port < 1 then return end
  if port ~= midi_out_port then
    midi_out = midi.connect(port)
    midi_out_port = port
  end
  local note = P.current_notes and P.current_notes[i]
  if note == nil then return end
  local ch = params:get("midi_ch")
  local dev = midi_out
  dev:note_on(note, 100, ch)
  clock.run(function()
    clock.sleep(params:get("midi_gate"))
    dev:note_off(note, 0, ch)
  end)
end

local function ping(i)
  if P.muted(i) then return end
  engine.trig(i - 1, 1)
  send_midi(i)
  flash[i] = 1
end

local function drop()
  sw:drop(params:get("phase"))
end

-- head positions, kept between runs so the wave continues on reload
local HEADS_FILE = norns.state.data .. "heads.data"

local function save_heads()
  local state = { phase = sw.phase, drift = drift_acc, wander = wander_pos }
  local ok, err = pcall(tab.save, state, HEADS_FILE)
  if not ok then print("talbot: could not save heads, " .. tostring(err)) end
end

-- the head's grid row, 1 at the top
local function head_row(i)
  return grid_rows - math.floor(sw:height(i) * (grid_rows - 1) + 0.5)
end

-- grid ---------------------------------------------------------------

function g.key(x, y, z)
  if x > N or y > grid_rows then return end
  if y == grid_rows then
    if z == 1 then
      params:set("mute" .. x, P.muted(x) and 1 or 2)
    end
    return
  end
  if z == 1 then
    sw:grab(x, (grid_rows - y) / (grid_rows - 1))
    if y == 1 then ping(x) end
  else
    sw:release(x)
  end
end

local function grid_redraw()
  -- follows a grid plugged in after load; a 256 grid gets longer pendulums
  if g.rows and g.rows > 0 then grid_rows = math.min(g.rows, 16) end
  g:all(0)
  for i = 1, N do
    local r = head_row(i)
    local muted = P.muted(i)

    -- the last two rows a head passed through, dimmer each step back
    local t = trail[i]
    if t[1] ~= r then
      t[2] = t[1]
      t[1] = r
    end
    if not muted then
      if t[2] then g:led(i, t[2], 3) end
      if flash[i] > 0.05 then
        g:led(i, 1, math.floor(4 + flash[i] * 11))
      end
    else
      g:led(i, grid_rows, 2)
    end

    local lv
    if sw.held[i] then lv = 15
    elseif muted then lv = 4
    else lv = 10 end
    g:led(i, r, lv)

    flash[i] = flash[i] * FLASH_DECAY
  end
  g:refresh()
end

-- lifecycle ----------------------------------------------------------

function init()
  P.on_rates = function() rates = P.rates(wander_off) end
  P.on_motion = function() sw:set_motion(params:get("motion")) end
  P.on_skew = function(d) sw:skew(d) end

  P.add_all()
  params:read()
  params:bang()

  rates = P.rates()
  sw:set_motion(params:get("motion"))

  -- carry on from where the last run left off. A first run joins the
  -- pattern as if it had been swinging since the clock started, so spread
  -- and phase shape the heads straight away.
  local saved = tab.load(HEADS_FILE)
  if type(saved) == "table" and sw:restore(saved.phase) then
    drift_acc = tonumber(saved.drift) or 0
    wander_pos = tonumber(saved.wander) or 0
  else
    sw:place(clock.get_beats() / params:get("period"), rates,
      params:get("phase"))
  end

  motion_clock = clock.run(function()
    local last = clock.get_beats()
    while true do
      clock.sleep(TICK)
      local now = clock.get_beats()
      local db = now - last
      last = now
      -- a transport jump or tempo reset is not motion
      if running and db > 0 and db < 1 then
        local period = params:get("period")
        local swings = db / period

        local d = params:get("drift") * swings
        if d ~= 0 then
          sw:drift(d)
          drift_acc = drift_acc + d
        end

        local depth = params:get("wander")
        local off = 0
        if depth > 0 then
          wander_pos = (wander_pos + swings / params:get("wander_rate")) % 1
          off = depth * math.sin(2 * math.pi * wander_pos)
        end
        if off ~= wander_off then
          wander_off = off
          rates = P.rates(wander_off)
        end

        for _, i in ipairs(sw:advance(db, period, rates)) do
          ping(i)
        end
      end
    end
  end)

  redraw_clock = clock.run(function()
    local frame = 0
    while true do
      clock.sleep(1 / FPS)
      grid_redraw()
      -- the screen is slower to draw and needs half the rate
      frame = frame + 1
      if frame % 2 == 0 then redraw() end
    end
  end)
end

function cleanup()
  if motion_clock then clock.cancel(motion_clock) end
  if redraw_clock then clock.cancel(redraw_clock) end
  params:write()
  save_heads()
end

-- controls -----------------------------------------------------------

-- the play page's head under K3 hold, as a height 0 to 1
local play_h = 0

local function play_enc(n, delta)
  if n == 2 then
    col = util.clamp(col + delta, 1, N)
  elseif n == 3 then
    if k3_held then
      -- reaching the top strikes, the same as pressing the grid's top row
      local was_top = play_h >= 1
      play_h = util.clamp(play_h + delta / 28, 0, 1)
      sw:grab(col, play_h)
      if play_h >= 1 and not was_top then ping(col) end
    else
      sw:nudge(col, delta / 96)
    end
  end
end

function enc(n, delta)
  if page == "play" then
    play_enc(n, delta)
    return
  end
  if n == 1 then
    row = util.clamp(row + delta, 1, ui.row_count())
  elseif n == 2 then
    params:delta(ui.ROWS[row].left[2], delta)
  elseif n == 3 then
    params:delta(ui.ROWS[row].right[2], delta)
  end
end

local function k3_hold_start()
  k3_held = true
  if page == "play" then
    play_h = sw:height(col)
    sw:grab(col, play_h)
  else
    drift_acc = 0
    drop()
  end
end

local function k3_tap()
  if page == "play" then
    params:set("mute" .. col, P.muted(col) and 1 or 2)
  else
    running = not running
  end
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      -- let go of a held head before leaving the page that holds it
      if k3_held and page == "play" then sw:release(col) end
      k3_held, k3_down = false, false
      if k3_clock then
        clock.cancel(k3_clock)
        k3_clock = nil
      end
      page = page == "params" and "play" or "params"
    end
  elseif n == 3 then
    if z == 1 then
      k3_down, k3_held = true, false
      if k3_clock then clock.cancel(k3_clock) end
      k3_clock = clock.run(function()
        clock.sleep(HOLD_TIME)
        k3_clock = nil
        if k3_down then k3_hold_start() end
      end)
    else
      if not k3_down then return end
      k3_down = false
      if k3_clock then
        clock.cancel(k3_clock)
        k3_clock = nil
      end
      if k3_held then
        if page == "play" then sw:release(col) end
        k3_held = false
      else
        k3_tap()
      end
    end
  end
end

function redraw()
  local heights, muted = {}, {}
  for i = 1, N do
    heights[i] = sw:height(i)
    muted[i] = P.muted(i)
  end
  if page == "play" then
    local note = P.current_notes and P.current_notes[col]
    ui.redraw_play({
      col = col, held = k3_held, running = running,
      heights = heights, flash = flash, muted = muted,
      note = note and MusicUtil.note_num_to_name(note, true),
    })
    return
  end
  ui.redraw({
    row = row, running = running,
    live = {
      -- what the heads are doing now, drift and wander included
      phase = params:get("phase") + drift_acc,
      spread = params:get("spread") + wander_off,
    },
    heights = heights, flash = flash, muted = muted,
  })
end

midi_in.event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" and d.vel > 0 and params:get("midi_root") == 1 then
    params:set("root_note", d.note)
  end
end
