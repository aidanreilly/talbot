# talbot

> **[Talbot effect](https://en.wikipedia.org/wiki/Talbot_effect)** /ˈtɔːlbət ɪˈfɛkt/ *n.* (*physics*) A diffraction effect in which a plane wave passing through a periodic grating forms images of the grating again at regular distances behind it.

talbot is a 16 note pendulum arpeggiator and wavetable synth for [monome norns](https://monome.org/docs/norns/) and a monome grid 128.

talbot uses the same ROM banks as [wavetables](https://github.com/aidanreilly/wavetables), through a variable slope low-pass filter.

## Install

Ensure norns is up to date. Visit <http://norns.local> and run `;install https://github.com/aidanreilly/talbot` in the maiden console.

Then `SYSTEM => RESET` to pick up the SuperCollider engine, and restart.

If you installed this script under an earlier name, delete the `~/dust/code/pendula` or `~/dust/code/talbots` folder before the reset. Otherwise the old engine compiles alongside this one on boot.

### Controls

`K2` flips the screen between the params page and the play page. The bottom of each page shows what the keys and encoders do there.

**Params page**

| Control | Action |
| --- | --- |
| `E1` | select row, scrolling for rows 7 to 9 |
| `E2` | edit left param |
| `E3` | edit right param |
| `K2` | to the play page |
| `K3` | run / stop |
| hold `K3` | drop all heads to the bottom |

**Play page**

The play page draws all 16 pendulums large, so you can play the heads without a grid.

| Control | Action |
| --- | --- |
| `E2` | select column |
| `E3` | nudge the column's head along its swing |
| `K2` | to the params page |
| `K3` | mute / unmute the column |
| hold `K3` + `E3` | grab the head and move it, reaching the top strikes the note |

Letting go of `K3` releases the head, and it carries on swinging from where you left it. Nudging with `E3` shifts one column out of step with the rest without stopping it, which is a quick way to break up a wave by hand.

### Grid

* Press the bottom row of a column to mute or unmute it. A muted column keeps swinging, dimmed, without sounding.
* Hold any other row to grab that column's head and pin it there. Let go and it carries on rising from where you held it. Grabbing a few heads at different heights is the quickest way to bend the wave by hand.
* Pressing the top row strikes the note straight away, and holds the head at the top until you let go.

### Motion params

These are the global params that shape the waves.

* `period` is the time in beats for column 1 to swing up and back. It follows the norns clock, so tempo changes and Link sync carry through.
* `spread` is how much faster each column runs than the one before it, as a percentage. At 0 every column swings together and you hear a 16 note chord. Small values give long slow waves, and larger values break the pattern into fast cross-rhythms. Negative values make the right side of the grid slower.
* `curve` decides how `spread` accumulates across the grid. `linear` adds the same step per column. `exp` compounds it, so the fast end races away. `centre` speeds up the outside columns and leaves the middle slow, so mirrored pairs swing together. `scatter` gives each column a fixed uneven offset.
* `phase` staggers the heads, so each column starts behind the one before it. At 1 the stagger covers one whole cycle across the grid and you get a travelling wave from the start. Turning it while the script runs slides the heads apart instead of restarting them.
* `drift` keeps adding phase while the pattern plays, measured per swing of column 1. At the default of 0.02, the stagger grows by one whole cycle across the grid every 50 swings, so the wave turns over slowly. Negative values pull the columns back together. At 0 the pattern repeats exactly.
* `wander` is how far `spread` drifts either side of its set value, as a percentage. `wander cycle`, in the params menu, sets how many swings of column 1 one full wander takes, for example 64. At 0 `spread` stays put.
* `motion` sets the swing shape. `pendulum` eases in and out at the top and bottom like a real pendulum. `bounce` moves at constant speed. `rise` climbs from bottom to top and snaps back, like a ramp.

The pattern always realigns at the bottom of the swing, which is where the heads start. In `pendulum` and `bounce` the realigned notes reach the top a moment apart, so the reunion sounds as a fast strum. In `rise` the top and the bottom are the same instant, so the reunion lands as one chord.

### Note params

* `root note` and `scale mode` generate 16 notes from the scale. A MIDI note on sets `root note`. Set `midi in sets root` to no to ignore it.
* `order` maps the scale notes to columns. `up` and `down` run low to high or high to low. `inward` puts the low notes at the edges and climbs to the middle. `outward` does the reverse. `scatter` is a fixed shuffle.

### Voice params

* `bank` and `wave` select the wavetable. `wave spread` fans the wave position across the columns, so column 16 sits up to 64 waves away from column 1.
* `morph` shifts the wave position on each strike and lets it settle back as the note decays.
* `cutoff`, `filter env`, and `slope` set the low-pass filter. `filter env` opens the cutoff by that many octaves on the strike.
* `attack` and `release` set the envelope. A column that pings again before its note has finished retriggers from the current level, so fast columns do not click.
* `ping` blends each voice from the wavetable (0) to a pinged resonant filter (1). Every strike sends a one-sample pulse into a resonator tuned to the column's note, so it rings like a [pinged filter](https://www.perfectcircuit.com/signal/modular-synthesizer-filter-pinging) in a modular patch. The low-pass filter still shapes the ring, so a low `cutoff` with a positive `filter env` gives a plucked, gated sound.
* `ring` is how long the resonator takes to die away by 60 dB, for example 1.2 s. The ring is its own envelope, so `attack` and `release` only shape the wavetable side.
* `drive`, in the params menu, saturates the ring. At 1 it is a pure sine. Higher values add the overtones of a filter pushed into self-oscillation.
* `pan spread` spreads the columns across the stereo field, left to right.
* `level` sets the output level.

### MIDI out

Each ping can also send a MIDI note. Set `device`, `channel`, and `gate` (the note length, for example 0.1 s) in the `midi out` group. Muted columns send nothing.

## Credits

Voice and wavetable loading based on [wavetables](https://github.com/aidanreilly/wavetables). Included wavetable ROMs are from [Synth Tech WaveEdit](https://synthtech.com/waveedit/).
