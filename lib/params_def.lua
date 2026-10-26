-- Param definitions

local swing = include("talbot/lib/swing")

local P = {}

P.N = 16
P.ORDERS = { "up", "down", "inward", "outward", "scatter" }

-- set by the script: called when anything the motion depends on changes
P.on_rates = function() end
P.on_motion = function() end
P.on_skew = function(_) end

local last_phase = nil

local function scale_names()
  local t = {}
  for i = 1, #MusicUtil.SCALES do
    table.insert(t, string.lower(MusicUtil.SCALES[i].name))
  end
  return t
end

-- Which scale degree each column plays. inward puts the low notes at the
-- edges and climbs to the middle, outward the reverse.
local function degree_order(order, n)
  local t = {}
  if order == 2 then
    for i = 1, n do t[i] = n + 1 - i end
  elseif order == 3 or order == 4 then
    local half = n // 2
    for k = 1, half do
      t[k] = 2 * k - 1
      t[n + 1 - k] = 2 * k
    end
    if n % 2 == 1 then t[half + 1] = n end
    if order == 4 then
      for i = 1, n do t[i] = n + 1 - t[i] end
    end
  elseif order == 5 then
    -- a fixed shuffle, so the same pset always plays the same pattern
    for i = 1, n do t[i] = i end
    local seed = 7
    for i = n, 2, -1 do
      seed = (seed * 1103515245 + 12345) % 2147483648
      local j = (seed % i) + 1
      t[i], t[j] = t[j], t[i]
    end
  else
    for i = 1, n do t[i] = i end
  end
  return t
end

function P.notes()
  local scale = MusicUtil.generate_scale_of_length(
    params:get("root_note"), params:get("scale_mode"), P.N)
  while #scale < P.N do table.insert(scale, scale[#scale]) end
  local order = degree_order(params:get("order"), P.N)
  local out = {}
  for i = 1, P.N do out[i] = scale[order[i]] end
  return out
end

function P.send_notes()
  local notes = P.notes()
  for i = 1, P.N do
    engine.hz(i - 1, MusicUtil.note_num_to_freq(notes[i]))
  end
  P.current_notes = notes
end

function P.send_waves()
  local w, spread = params:get("wave"), params:get("wave_spread")
  for i = 1, P.N do
    engine.wave(i - 1, w + spread * (i - 1) / (P.N - 1))
  end
end

P.PANS = { "centre", "l/r" }

-- centre puts every column in the middle. l/r sends odd columns hard left
-- and even columns hard right.
function P.send_pans()
  local alt = params:get("pan") == 2
  for i = 1, P.N do
    local p = 0
    if alt then p = (i % 2 == 1) and -1 or 1 end
    engine.pan(i - 1, p)
  end
end

-- extra is the wander offset, in the same percent units as spread
function P.rates(extra)
  return swing.rates(P.N, (params:get("spread") + (extra or 0)) / 100,
    params:get("curve"))
end

function P.muted(i)
  return params:get("mute" .. i) == 2
end

local function midi_ports()
  local t = { "off" }
  for i = 1, #midi.vports do
    t[i + 1] = i .. ": " .. util.trim_string_to_width(midi.vports[i].name, 60)
  end
  return t
end

function P.add_all()
  params:add_separator("talbot_motion", "motion")

  params:add_control("period", "period",
    controlspec.new(0.25, 64, "exp", 0, 4, "beats"))
  params:set_action("period", function() P.on_rates() end)

  params:add_control("spread", "spread",
    controlspec.new(-10, 25, "lin", 0.05, 6.25, "%"))
  params:set_action("spread", function() P.on_rates() end)

  params:add_option("curve", "curve", swing.CURVES, 1)
  params:set_action("curve", function() P.on_rates() end)

  params:add_control("phase", "phase",
    controlspec.new(0, 4, "lin", 0.01, 0, ""))
  params:set_action("phase", function(x)
    if last_phase ~= nil then P.on_skew(x - last_phase) end
    last_phase = x
  end)

  -- drift keeps adding to the stagger while the pattern plays, in phase per
  -- swing of column 1, so the wave never settles into one shape
  params:add_control("drift", "drift",
    controlspec.new(-0.25, 0.25, "lin", 0.001, 0.02, ""))

  -- wander swings spread up and down slowly around its set value
  params:add_control("wander", "wander",
    controlspec.new(0, 10, "lin", 0.05, 1.5, "%"))
  params:add_control("wander_rate", "wander cycle",
    controlspec.new(4, 512, "exp", 0, 64, "swings"))

  params:add_option("motion", "motion", swing.MOTIONS, 1)
  params:set_action("motion", function() P.on_motion() end)

  params:add_separator("talbot_notes", "notes")

  params:add{ type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 48,
    formatter = function(p) return MusicUtil.note_num_to_name(p:get(), true) end,
    action = function() P.send_notes() end }

  params:add_option("scale_mode", "scale mode", scale_names(), 5)
  params:set_action("scale_mode", function() P.send_notes() end)

  params:add_option("order", "order", P.ORDERS, 1)
  params:set_action("order", function() P.send_notes() end)

  params:add_option("midi_root", "midi in sets root", { "yes", "no" }, 1)

  params:add_separator("talbot_voice", "voice")

  params:add_number("bank", "bank", 1, 3, 1)
  params:set_action("bank", function(x) engine.bank(x) end)

  params:add_control("wave", "wave",
    controlspec.new(0, 64, "lin", 0.1, 8, ""))
  params:set_action("wave", function() P.send_waves() end)

  params:add_control("wave_spread", "wave spread",
    controlspec.new(-64, 64, "lin", 0.1, 0, ""))
  params:set_action("wave_spread", function() P.send_waves() end)

  params:add_control("morph", "morph",
    controlspec.new(-32, 32, "lin", 0.1, 6, ""))
  params:set_action("morph", function(x) engine.morph(x) end)

  -- one AD envelope drives both the amp and the filter
  params:add_control("attack", "attack",
    controlspec.new(0.001, 2, "exp", 0, 0.005, "s"))
  params:set_action("attack", function(x) engine.attack(x) end)

  params:add_control("decay", "decay",
    controlspec.new(0.02, 8, "exp", 0, 0.6, "s"))
  params:set_action("decay", function(x) engine.decay(x) end)

  params:add_control("cutoff", "cutoff",
    controlspec.new(40, 18000, "exp", 0, 800, "hz"))
  params:set_action("cutoff", function(x) engine.cutoff(x) end)

  params:add_control("env_cut", "filter env",
    controlspec.new(-4, 6, "lin", 0.05, 3, "oct"))
  params:set_action("env_cut", function(x) engine.env_cut(x) end)

  params:add_control("resonance", "resonance",
    controlspec.new(0, 1, "lin", 0.01, 0.2, ""))
  params:set_action("resonance", function(x) engine.resonance(x) end)

  params:add_option("pan", "pan", P.PANS, 1)
  params:set_action("pan", function() P.send_pans() end)

  params:add_control("level", "level",
    controlspec.new(0, 1, "lin", 0.01, 0.6, ""))
  params:set_action("level", function(x) engine.level(x) end)

  params:add_group("midi out", 3)
  params:add_option("midi_out", "device", midi_ports(), 1)
  params:add_number("midi_ch", "channel", 1, 16, 1)
  params:add_control("midi_gate", "gate",
    controlspec.new(0.01, 2, "exp", 0, 0.1, "s"))

  params:add_group("columns", P.N)
  for i = 1, P.N do
    params:add_option("mute" .. i, "column " .. i, { "on", "muted" }, 1)
  end
end

return P
