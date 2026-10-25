-- The pendulum

local swing = {}

swing.MOTIONS = { "pendulum", "bounce", "rise" }
swing.CURVES = { "linear", "exp", "centre", "scatter" }

-- slowest a column may run, relative to column 1
local MIN_RATE = 1 / 32

local function frac(x)
  return x - math.floor(x)
end

-- Where the top sits in a cycle. The swinging motions peak half way through,
-- rise peaks at the wrap.
local function top_offset(motion)
  if motion == 3 then return 0 end
  return 0.5
end

-- Fixed per-column scatter, the same on every load so a pset sounds the same
-- twice. Golden ratio steps spread evenly without repeating.
local function scatter(i)
  return frac((i - 1) * 0.6180339887)
end

-- Column speeds relative to column 1. spread is the fraction one column
-- gains on the one before it; curve decides how the gains add up across
-- the grid.
function swing.rates(n, spread, curve)
  local r = {}
  local span = n - 1
  local mid = (n + 1) / 2
  for i = 1, n do
    local v
    if curve == 2 then
      v = (1 + spread) ^ (i - 1)
    elseif curve == 3 then
      -- edges fast, middle slow, so mirrored pairs swing together
      v = 1 + spread * math.abs(i - mid) * (span / (mid - 1))
    elseif curve == 4 then
      v = 1 + spread * span * scatter(i)
    else
      v = 1 + spread * (i - 1)
    end
    r[i] = math.max(MIN_RATE, v)
  end
  return r
end

-- Head height for a phase, 0 at the bottom and 1 at the top.
function swing.height(motion, phase)
  local f = frac(phase)
  if motion == 2 then
    return f < 0.5 and f * 2 or 2 - f * 2
  elseif motion == 3 then
    return f
  end
  return (1 - math.cos(2 * math.pi * f)) / 2
end

-- The rising phase that puts a head at height h.
local function inverse(motion, h)
  h = math.max(0, math.min(1, h))
  if motion == 2 then
    return h / 2
  elseif motion == 3 then
    return h
  end
  return math.acos(1 - 2 * h) / (2 * math.pi)
end

local Swing = {}
Swing.__index = Swing

function swing.new(n)
  local s = setmetatable({ n = n, phase = {}, last = {}, held = {} }, Swing)
  s.motion = 1
  for i = 1, n do
    s.phase[i] = 0
    s.last[i] = 0
  end
  return s
end

-- Re-reads which top each column last passed, without pinging. Anything
-- that moves a phase by hand or moves the top calls this.
function Swing:settle(i)
  self.last[i] = math.floor(self.phase[i] + top_offset(self.motion))
end

function Swing:set_motion(motion)
  self.motion = motion
  for i = 1, self.n do self:settle(i) end
end

-- Drops every head to the bottom together. offset staggers them: each column
-- starts that fraction of a cycle behind the one before, scaled across the
-- grid so offset 1 spreads one whole cycle over all 16.
function Swing:drop(offset)
  for i = 1, self.n do
    self.phase[i] = -offset * (i - 1) / self.n
    self:settle(i)
  end
end

-- Puts every head where it would be after the pattern had already run for
-- cycles cycles of column 1, with the stagger applied. Spread and phase are
-- in play from the first frame, so the heads begin mid-wave.
function Swing:place(cycles, rates, offset)
  for i = 1, self.n do
    self.phase[i] = cycles * rates[i] - offset * (i - 1) / self.n
    self:settle(i)
  end
end

-- Picks up phases saved by a previous run. Ignores anything malformed.
function Swing:restore(phases)
  if type(phases) ~= "table" or #phases ~= self.n then return false end
  for i = 1, self.n do
    if type(phases[i]) ~= "number" or phases[i] ~= phases[i] then return false end
  end
  for i = 1, self.n do
    self.phase[i] = phases[i]
    self:settle(i)
  end
  return true
end

-- Slides the stagger by d without re-reading the tops, so a drift applied
-- in the same tick as advance still pings exactly once per crossing.
function Swing:drift(d)
  for i = 1, self.n do
    if not self.held[i] then
      self.phase[i] = self.phase[i] - d * (i - 1) / self.n
    end
  end
end

-- Slides one column's head along its swing by d cycles, without pinging.
function Swing:nudge(i, d)
  self.phase[i] = self.phase[i] + d
  self:settle(i)
end

-- Moves the stagger while running, so the change slides the heads instead
-- of restarting them.
function Swing:skew(d)
  for i = 1, self.n do
    self.phase[i] = self.phase[i] - d * (i - 1) / self.n
    self:settle(i)
  end
end

-- Advances every free column by dbeats. Returns the columns that crossed
-- a top. A column that crosses more than once in one step pings once.
function Swing:advance(dbeats, period, rates)
  local hits = {}
  local c = top_offset(self.motion)
  local step = dbeats / period
  for i = 1, self.n do
    if not self.held[i] then
      self.phase[i] = self.phase[i] + step * rates[i]
      local idx = math.floor(self.phase[i] + c)
      if idx > self.last[i] then hits[#hits + 1] = i end
      self.last[i] = idx
    end
  end
  return hits
end

-- Holds a column's head at height h, on the rising side, until let go.
-- A head held at the top has already passed it, so letting go does not ping.
function Swing:grab(i, h)
  self.held[i] = h
  self.phase[i] = math.floor(self.phase[i]) + inverse(self.motion, h)
  self:settle(i)
end

function Swing:release(i)
  self.held[i] = nil
end

function Swing:height(i)
  if self.held[i] then return self.held[i] end
  return swing.height(self.motion, self.phase[i])
end

return swing
