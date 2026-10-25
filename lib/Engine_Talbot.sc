// talbot: 16 wavetable voices pinging resonant filters

Engine_Talbot : CroneEngine {
  classvar numVoices = 16;
  classvar wavesPerBank = 64;
  classvar slotsPerBank = 65;
  classvar numBanks = 3;
  classvar waveLen = 256;

  var <voices, <bus, <outputStage, <bufs, wtBase;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  wavePath {
    ^PathName(this.class.filenameSymbol.asString).pathOnly ++ "waves/";
  }

  bankOffset { arg bank;
    ^wtBase + ((bank.clip(1, numBanks) - 1) * slotsPerBank);
  }

  // Slices each 64-wave bank into wavetable signals, plus a copy of wave 1
  // in slot 64 so a position of 64 still reads a real table.
  loadBanks { arg server;
    var dir = this.wavePath;
    var wts = Array.new(numBanks * slotsPerBank);
    var out;

    ["rom_a.wav", "rom_b.wav", "rom_c.wav"].do({ arg name;
      var frames = FloatArray.newClear(wavesPerBank * waveLen);
      var sf = SoundFile.openRead(dir ++ name);
      if (sf.isNil) { Error("talbot: cannot open" + dir ++ name).throw };
      sf.readData(frames);
      sf.close;
      wavesPerBank.do({ arg w;
        wts = wts.add(Signal.newFrom(
          frames.copyRange(w * waveLen, ((w + 1) * waveLen) - 1)).asWavetable);
      });
      wts = wts.add(Signal.newFrom(frames.copyRange(0, waveLen - 1)).asWavetable);
    });

    out = Buffer.allocConsecutive(wts.size, server, waveLen * 2, 1);
    server.sync;
    wts.do({ arg wt, i; out[i].sendCollection(wt, 0, 0.002) });
    server.sync;
    ^out;
  }

  alloc {
    var server = context.server;

    bufs = this.loadBanks(server);
    if (bufs.isNil or: { bufs.size != (numBanks * slotsPerBank) }) {
      Error("talbot: could not allocate the wave buffers"
        + "- raise scsynth's -b setting").throw;
    };
    wtBase = bufs[0].bufnum;

    SynthDef(\talbotVoice, {
      arg out = 0, bufOffset = 0,
          hz = 220, wave = 0, morph = 0,
          t_trig = 0, amp = 1,
          atk = 0.004, rel = 0.6,
          cutoff = 4000, envCut = 2, slope = 2,
          ping = 0, ring = 1.2, drive = 1.5,
          pan = 0;

      var env, vel, freq, pos, sig, res, tau, cut, coef,
          t1, t2, t3, t4, taps, idx, lo, frac;

      // One shot per trigger. Retriggering heads to the peak from wherever
      // the envelope is, never from zero.
      env = EnvGen.kr(Env([0, 1, 0], [atk, rel], [0, -4]), t_trig);
      vel = Latch.kr(amp, t_trig);
      freq = Lag.kr(hz, 0.005);

      // morph sweeps the wave on the strike and lets it settle back
      pos = (Lag.kr(wave, 0.05) + (morph * env)).clip(0, wavesPerBank);
      sig = VOsc.ar(bufOffset + pos, freq) * env;

      // Filter pinging: the enveloped wavetable strikes a resonator tuned to
      // the note, and ring sets the time to die away by 60 dB. 13.8 / (ring *
      // sr) is unity gain at the note, and 1.5 makes up for the harmonics the
      // ring drops. A short burst builds less ring than a long one, so the
      // gain also makes up for the burst's length (about atk / 2 + 0.23 *
      // rel for this envelope) against the ring's time constant. drive
      // saturates the ring for the overtones a self-oscillating analog
      // filter adds. One resonator makes a peak only 1 / (pi * ring) Hz
      // wide, so three spread 7 cents around the note widen it, with the
      // centre weighted double so a long burst at the note still builds.
      tau = ring / 6.91;
      res = (Ringz.ar(sig, freq * (2 ** ([-7, 0, 7] / 1200)), ring,
        1.5 * 13.8 * SampleDur.ir / ring) * [0.25, 0.5, 0.25]).sum
        / (1 - exp(((atk * 0.5) + (rel * 0.23)).neg / tau)).max(0.001);
      res = (res * drive).tanh / drive.tanh;
      sig = (sig * (1 - ping)) + (res * ping);

      // the filter opens envCut octaves on the strike
      cut = (cutoff * (2 ** (envCut * env))).clip(20, 18000);
      coef = exp(-2pi * cut * SampleDur.ir).clip(0, 0.9999);
      t1 = OnePole.ar(sig, coef);
      t2 = OnePole.ar(t1, coef);
      t3 = OnePole.ar(t2, coef);
      t4 = OnePole.ar(t3, coef);
      taps = [t1, t2, t3, t4];
      idx = slope.clip(0, 3);
      lo = idx.floor;
      frac = idx - lo;
      sig = (Select.ar(lo, taps) * (1 - frac))
        + (Select.ar((lo + 1).min(3), taps) * frac);

      Out.ar(out, Pan2.ar(LeakDC.ar(sig) * vel,
        Lag.kr(pan, 0.05)));
    }).add;

    // 16 voices peaking together at a drop need headroom before the limiter
    SynthDef(\talbotOut, { arg in = 0, out = 0, level = 0.5;
      var sig = In.ar(in, 2) * Lag.kr(level, 0.05) * 0.4;
      Out.ar(out, Limiter.ar(sig, 0.98, 0.01));
    }).add;

    server.sync;

    bus = Bus.audio(server, 2);
    server.sync;

    voices = Array.fill(numVoices, {
      Synth.new(\talbotVoice, [\out, bus, \bufOffset, this.bankOffset(1)],
        target: context.xg);
    });

    outputStage = Synth.new(\talbotOut, [\in, bus, \out, context.out_b],
      target: context.xg, addAction: \addToTail);
    server.sync;

    this.addCommands;
  }

  addCommands {
    // per-voice
    [[\hz, \hz], [\wave, \wave], [\pan, \pan]].do({ arg pair;
      var argName = pair[1];
      this.addCommand(pair[0], "if", { arg msg;
        var i = msg[1].asInteger;
        if ((i >= 0) and: { i < numVoices }) { voices[i].set(argName, msg[2]) };
      });
    });

    this.addCommand(\trig, "if", { arg msg;
      var i = msg[1].asInteger;
      if ((i >= 0) and: { i < numVoices }) {
        voices[i].set(\amp, msg[2], \t_trig, 1);
      };
    });

    // global, written to every voice
    [
      [\attack, \atk], [\release, \rel], [\morph, \morph],
      [\cutoff, \cutoff], [\env_cut, \envCut], [\slope, \slope],
      [\ping, \ping], [\ring, \ring], [\drive, \drive]
    ].do({ arg pair;
      var argName = pair[1];
      this.addCommand(pair[0], "f", { arg msg;
        voices.do({ arg v; v.set(argName, msg[1]) });
      });
    });

    this.addCommand(\bank, "i", { arg msg;
      var off = this.bankOffset(msg[1].asInteger);
      voices.do({ arg v; v.set(\bufOffset, off) });
    });

    this.addCommand(\level, "f", { arg msg;
      outputStage.set(\level, msg[1]);
    });
  }

  free {
    if (voices.notNil) { voices.do({ arg v; v.free }) };
    if (outputStage.notNil) { outputStage.free };
    if (bus.notNil) { bus.free };
    if (bufs.notNil) { bufs.do({ arg b; b.free }) };
  }
}
