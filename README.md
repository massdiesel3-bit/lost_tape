# lost tape

**Ambient granular synthesizer for Norns Shield**  
*Version 1.0*

---

## Concept

Lost Tape is a granular synthesizer designed for slow, evolving ambient textures. Inspired by the [LemonDrop](https://1010music.com/) by 1010 Music, it transforms any audio sample into a living, breathing soundscape through granular synthesis, tape coloring effects, and a musical step sequencer.

The instrument is built around the idea of sound that feels worn, imperfect, and alive — like a tape loop left running too long.

---

## Requirements

- Norns Shield (RPi4B recommended)
- Audio sample loaded in `dust/audio/`

---

## Installation

```
;install https://github.com/yourusername/lost_tape
```

Or manually copy to `dust/code/lost_tape/`.

Place your audio samples in `dust/audio/`. Select a sample via **PARAMETERS > sample**.

---

## Interface

The screen is divided into two zones:

- **Top** — dynamic visual (waveform, grain activity, effects visualization)
- **Bottom** — 3 scrollable parameters with value bars

Navigation uses **4 dots** in the top-right corner indicating the current page.

---

## Global Controls

| Control | Function |
|---|---|
| **E1** | Navigate pages (GRAINS → DELAY → TAPE → SEQ) |
| **K3** | Master play / stop (engine + sequencer together) |

---

## Page 1 — GRAINS

The core granular engine. Reads tiny fragments (grains) of the loaded sample and scatters them to build textures.

**Visual:** waveform with a grey zone showing grain size, bright cursor showing position, dynamic lines showing grain triggers.

| Control | Function |
|---|---|
| E2 | Scroll parameter list |
| E3 | Modify selected parameter |
| K2 | Reset parameter to default |

| Parameter | Description |
|---|---|
| **POS** | Position in the sample (0 → 1) |
| **SIZE** | Grain duration (0.01s → 1.0s) |
| **DENSITY** | Grains per second (0.5 → 15) |
| **PITCH** | Playback rate (0.1 → 2.0) |
| **PAN** | Stereo position |
| **JITTER** | Random position scatter per grain |
| **SPREAD** | Random stereo spread per grain |
| **ENV ATK** | Grain envelope attack |
| **ENV REL** | Grain envelope release |
| **AMP** | Output level |
| **REVERSE** | Reverse grain playback (ON/OFF) |

> Grain amplitude is automatically scaled by polyphony to prevent saturation as density and size increase.

---

## Page 2 — DELAY

Tape-style delay and reverb. The visual shows delay echoes as fading cursor copies with wow & flutter drift.

| Parameter | Description |
|---|---|
| **DEL TIME** | Delay time in musical values (1/16 → 1 BAR), synced to clock |
| **FEEDBACK** | Delay feedback amount |
| **DEL MIX** | Delay wet/dry |
| **REV SIZE** | Reverb room size |
| **REV DAMP** | Reverb high-frequency damping |
| **REV MIX** | Reverb wet/dry |

> Delay time changes are smoothed over 50ms to avoid clicks.

---

## Page 3 — TAPE

Tape coloring effects applied to the whole signal. The noise (hiss) is added after filtering to preserve its raw cassette character. Visual shows the signal deformed by wow & flutter in real time.

| Parameter | Description |
|---|---|
| **FILT HZ** | Resonant filter cutoff (200Hz → 20KHz) |
| **FILT RES** | Filter resonance |
| **WOW** | Slow pitch modulation (0.5Hz) |
| **FLUTTER** | Fast random pitch modulation (12Hz) |
| **SATURATE** | Tape saturation / soft overdrive |
| **NOISE** | Tape hiss level |
| **LOFI HZ** | High-frequency rolloff cutoff |

> A small square appears in the top-right of the waveform when saturation is clipping.

---

## Page 4 — SEQ

A 16-step musical sequencer. Each step stores a **gate** (on/off) and a **pitch** expressed as a scale degree. Bar height in the grid represents note pitch.

**Visual:** step grid where lit bars show active gates, bar height = note pitch, bright indicator = current playing step.

| Control | Function |
|---|---|
| E2 | Move step cursor |
| E3 | Change note of selected step (scale degrees) |
| K2 | Toggle gate of selected step (on/off) |
| K3 | Play / stop sequencer |

The sequencer starts on step 1 immediately on play, then follows the clock.

**Global sequencer settings (PARAMETERS menu):**

| Parameter | Description |
|---|---|
| SEQ LENGTH | Number of active steps (2 → 16) |
| SEQ DIV | Step duration (1/4 → 8 BAR) |
| SEQ SCALE | Musical scale (Major, Minor, Pentatonic, Dorian, Lydian, Mixo, Chromatic) |
| SEQ ROOT | Root note semitone offset (C → B) |
| SEQ OCTAVE | Base octave (-2 → +2) |

---

## M8 Tracker Sync

Lost Tape supports MIDI clock sync with the Dirtywave M8 (or any MIDI clock source):

1. Connect the M8 via USB
2. On Norns: **PARAMETERS > clock source → midi**
3. The sequencer and delay time automatically follow the M8 tempo

---

## Signal Chain

```
Sample
  └─ Granular engine (GrainBuf)
       └─ Delay (CombC)
            └─ Reverb (FreeVerb2)
                 └─ Resonant filter (RLPF)
                      └─ Lo-fi filter (LPF)
                           └─ Tape noise (PinkNoise)
                                └─ Saturation (softclip)
                                     └─ Output
```

---

## Tips

- Start with long grains (SIZE > 0.4s) and low density (2–4) for deep ambient pads
- Set JITTER to 0.05–0.1 for natural movement without losing the position anchor
- Use the SEQ page with slow DIV (2 BAR or 4 BAR) and a pentatonic scale for effortless harmonic evolution
- WOW at 0.2–0.3 adds organic instability without sounding like an effect
- Route the M8 as MIDI clock and set DEL TIME to 1/4 for tempo-synced echo

---

## Credits

Built with [Norns](https://monome.org/norns/) and SuperCollider.  
Granular engine architecture inspired by [glut](https://github.com/artfwo/glut) by artfwo.  
Concept inspired by the LemonDrop granular sampler by 1010 Music.

