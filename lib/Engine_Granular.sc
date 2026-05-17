// Engine_Granular.sc
// Lost Tape - Phase 6 : filtre RLPF + polish
// Chaine FX : delay -> reverb -> RLPF(musical) -> LPF(lofi) -> noise -> softclip
// Noise apres les filtres = hiss cassette pur et non filtre
// dust/code/lost_tape/lib/Engine_Granular.sc

Engine_Granular : CroneEngine {

    var buf, envBuf, synth, fx, mixBus, pg;
    var env_atk, env_rel;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    setEnvelope { arg atk, rel;
        var sus = max(0.001, 1.0 - atk - rel);
        var sig = Env.new([0,1,1,0],[atk,sus,rel],[\sin,\lin,\sin]).asSignal(256);
        envBuf.sendCollection(sig);
    }

    alloc {
        env_atk = 0.1; env_rel = 0.3;
        buf    = Buffer.alloc(context.server, context.server.sampleRate.asInteger, 1);
        envBuf = Buffer.alloc(context.server, 256, 1);
        this.setEnvelope(env_atk, env_rel);

        // ---- Granulaire + wow/flutter ----
        SynthDef(\lost_tape_grain, {
            arg out=0, buf=0, envbuf=0,
                pos=0.5,    size=0.1,  density=10,
                pitch=1.0,  pan=0.0,   amp=0.8,
                jitter=0.0, spread=0.0, reverse=0,
                wow=0.0,    flutter=0.0;

            var d       = density.clip(0.5, 15.0);
            var sz      = size.clip(0.01, 1.0);
            var trigger = Impulse.kr(d);
            var jit     = TRand.kr(trig: trigger, lo: jitter.neg, hi: jitter);
            var pan_rnd = TRand.kr(trig: trigger, lo: spread.neg, hi: spread);
            var pos_sig = (pos + jit).clip(0.0, 1.0);
            var wow_lfo     = SinOsc.kr(0.5)  * wow     * 0.02;
            var flutter_lfo = LFNoise1.kr(12) * flutter * 0.008;
            var rate_final  = pitch * (1.0 + wow_lfo + flutter_lfo) * (1.0 - (reverse * 2.0));
            var grain = GrainBuf.ar(
                numChannels: 1, trigger: trigger, dur: sz, sndbuf: buf,
                rate: rate_final, pos: pos_sig, interp: 2, pan: 0, envbufnum: envbuf
            );

            // Scale par 1/sqrt(grains simultanes) pour eviter la saturation par accumulation
            // grains simultanes attendus = density * size
            var poly_scale = (1.0 / (d * sz).sqrt).clip(0.1, 1.0);

            Out.ar(out, Balance2.ar(grain, grain, pan + pan_rnd) * amp * poly_scale);
        }).add;

        // ---- FX : delay -> reverb -> filtre RLPF -> lofi LPF -> noise -> softclip ----
        SynthDef(\lost_tape_fx, {
            arg in=0, out=0,
                del_time=0.25, del_fb=0.4,    del_mix=0.3,
                rev_size=0.5,  rev_damp=0.5,   rev_mix=0.2,
                filt_hz=20000, filt_res=0.0,
                tape_sat=0.0,  tape_noise=0.0,  tape_lp=20000;

            var sig       = In.ar(in, 2);
            var smooth_dt = Lag.kr(del_time, 0.05);   // 50ms : transitions sans clics
            var decaytime = (-6.9078 * smooth_dt) / del_fb.max(0.001).log;
            var delayed   = CombC.ar(sig, 2.0, smooth_dt, decaytime.clip(0.01, 30.0));
            var del_wet   = XFade2.ar(sig, delayed, del_mix * 2 - 1);
            var rev       = FreeVerb2.ar(del_wet[0], del_wet[1], rev_mix, rev_size, rev_damp);

            // Filtre RLPF musical (sur le signal, avant le hiss)
            // rq = reciproque du Q : rq=1 = pas de resonance, rq=0.05 = tres resonant
            var rq    = (1.0 - filt_res * 0.95).max(0.01);
            var filtL = RLPF.ar(rev[0], filt_hz.max(200), rq);
            var filtR = RLPF.ar(rev[1], filt_hz.max(200), rq);

            // Tape : lofi LPF -> noise (apres filtres = hiss pur) -> softclip
            var tapeL  = LPF.ar(filtL, tape_lp.max(200));
            var tapeR  = LPF.ar(filtR, tape_lp.max(200));
            var noiseL = PinkNoise.ar(tape_noise * 0.02);
            var noiseR = PinkNoise.ar(tape_noise * 0.02);
            // Saturation : crossfade dry/wet
            // tape_sat=0 -> signal pur (pas de softclip)
            // tape_sat=1 -> saturation complete
            var drive   = 1.0 + tape_sat * 3.0;
            var satL    = (tapeL + noiseL) * drive;
            var satR    = (tapeR + noiseR) * drive;
            var outL    = XFade2.ar(tapeL + noiseL, satL.softclip / drive, tape_sat * 2 - 1);
            var outR    = XFade2.ar(tapeR + noiseR, satR.softclip / drive, tape_sat * 2 - 1);

            Out.ar(out, [outL, outR]);
        }).add;

        context.server.sync;

        mixBus = Bus.audio(context.server, 2);

        fx = Synth.new(\lost_tape_fx, [
            \in, mixBus.index, \out, context.out_b.index,
            \del_time, 0.25, \del_fb, 0.4,  \del_mix, 0.3,
            \rev_size, 0.5,  \rev_damp, 0.5, \rev_mix, 0.2,
            \filt_hz, 20000, \filt_res, 0.0,
            \tape_sat, 0.0,  \tape_noise, 0.0, \tape_lp, 20000
        ], target: context.xg);

        pg    = ParGroup.head(context.xg);
        synth = Synth.new(\lost_tape_grain, [
            \out, mixBus.index, \buf, buf.bufnum, \envbuf, envBuf.bufnum,
            \pos, 0.5, \size, 0.1, \density, 10,
            \pitch, 1.0, \pan, 0.0, \amp, 0.8,
            \jitter, 0.0, \spread, 0.0, \reverse, 0,
            \wow, 0.0, \flutter, 0.0
        ], target: pg);

        context.server.sync;

        this.addCommand("read_buf","s",{ arg msg;
            Buffer.readChannel(context.server, msg[1].asString, 0, -1, [0], { arg b;
                buf.free; buf=b; synth.set(\buf, buf.bufnum);
                ("loaded -> "++msg[1]).postln;
            });
        });
        this.addCommand("env_attack",  "f",{arg msg; env_atk=msg[1].clip(0,0.49); this.setEnvelope(env_atk,env_rel);});
        this.addCommand("env_release", "f",{arg msg; env_rel=msg[1].clip(0,0.49); this.setEnvelope(env_atk,env_rel);});
        this.addCommand("pos",     "f",{arg msg; synth.set(\pos,     msg[1]);});
        this.addCommand("size",    "f",{arg msg; synth.set(\size,    msg[1].clip(0.01,1.0));});
        this.addCommand("density", "f",{arg msg; synth.set(\density, msg[1].clip(0.5,15.0));});
        this.addCommand("pitch",   "f",{arg msg; synth.set(\pitch,   msg[1].clip(0.1,2.0));});
        this.addCommand("pan",     "f",{arg msg; synth.set(\pan,     msg[1].clip(-1,1));});
        this.addCommand("amp",     "f",{arg msg; synth.set(\amp,     msg[1].clip(0,1));});
        this.addCommand("jitter",  "f",{arg msg; synth.set(\jitter,  msg[1].clip(0,0.5));});
        this.addCommand("spread",  "f",{arg msg; synth.set(\spread,  msg[1].clip(0,1));});
        this.addCommand("reverse", "f",{arg msg; synth.set(\reverse, msg[1]);});
        this.addCommand("wow",     "f",{arg msg; synth.set(\wow,     msg[1].clip(0,1));});
        this.addCommand("flutter", "f",{arg msg; synth.set(\flutter, msg[1].clip(0,1));});
        this.addCommand("del_time",   "f",{arg msg; fx.set(\del_time,   msg[1].clip(0.01,1));});
        this.addCommand("del_fb",     "f",{arg msg; fx.set(\del_fb,     msg[1].clip(0,0.95));});
        this.addCommand("del_mix",    "f",{arg msg; fx.set(\del_mix,    msg[1].clip(0,1));});
        this.addCommand("rev_size",   "f",{arg msg; fx.set(\rev_size,   msg[1].clip(0,1));});
        this.addCommand("rev_damp",   "f",{arg msg; fx.set(\rev_damp,   msg[1].clip(0,1));});
        this.addCommand("rev_mix",    "f",{arg msg; fx.set(\rev_mix,    msg[1].clip(0,1));});
        this.addCommand("filt_hz",    "f",{arg msg; fx.set(\filt_hz,    msg[1].clip(200,20000));});
        this.addCommand("filt_res",   "f",{arg msg; fx.set(\filt_res,   msg[1].clip(0,1));});
        this.addCommand("tape_sat",   "f",{arg msg; fx.set(\tape_sat,   msg[1].clip(0,1));});
        this.addCommand("tape_noise", "f",{arg msg; fx.set(\tape_noise, msg[1].clip(0,1));});
        this.addCommand("tape_lp",    "f",{arg msg; fx.set(\tape_lp,    msg[1].clip(200,20000));});
    }

    free {
        synth.free; fx.free; pg.free;
        mixBus.free; buf.free; envBuf.free;
    }
}
