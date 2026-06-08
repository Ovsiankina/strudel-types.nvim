// Hand-tuned bits the auto-generator can't infer well.
//
// - signals: globals that are Pattern *values*, not functions (so `sine`, not `sine()`).
// - overrides: precise argument lists for hot functions. `args` is used verbatim for
//   both the global `const name: (args) => Pattern` and the `Pattern` method `name(args)`.
//   (No `...args` is appended for overrides — they are intentional.)
//
// Everything not listed here is auto-generated from doc.json with documented params.

export const signals = [
  'silence',
  'sine', 'cosine', 'saw', 'isaw', 'tri', 'square', 'pulse',
  'rand', 'perlin', 'time',
  'pink', 'brown', 'white',
  'mousex', 'mousey',
];

export const overrides = {
  // sources
  note: { args: 'notes?: StrudelInput' },
  n: { args: 'n?: StrudelInput' },
  s: { args: 'sound?: string | Pattern' },
  sound: { args: 'sound?: string | Pattern' },
  // effects / params
  gain: { args: 'amount?: number | Pattern' },
  cutoff: { args: 'frequency?: number | Pattern' },
  lpf: { args: 'frequency?: number | Pattern' },
  hpf: { args: 'frequency?: number | Pattern' },
  room: { args: 'level?: number | Pattern' },
  delay: { args: 'amount?: number | Pattern' },
  pan: { args: 'position?: number | Pattern' },
  speed: { args: 'factor?: number | Pattern' },
  // time
  slow: { args: 'factor?: number | Pattern' },
  fast: { args: 'factor?: number | Pattern' },
  rev: { args: '' },
  // structure / higher-order
  jux: { args: 'fn: (pat: Pattern) => Pattern' },
  every: { args: 'n: number | Pattern, fn: (pat: Pattern) => Pattern' },
  off: { args: 'time: number | Pattern, fn: (pat: Pattern) => Pattern' },
  struct: { args: 'struct?: string | Pattern' },
  // music theory
  scale: { args: 'scale?: string | Pattern' },
};

// Real Strudel API that is NOT in doc.json (undocumented, or REPL/inner scope, or
// the underscore "draw-only" visual variants). Hand-declared so they get completion
// + hover instead of falling back to `any` / the index signature.
//   global: emit as a bare global function     method: emit as a Pattern/String method
export const extras = {
  setcps: { args: 'cps?: number', global: true, method: false, desc: 'Set the tempo in cycles per second.' },
  setCps: { args: 'cps?: number', global: true, method: false, desc: 'Set the tempo in cycles per second (alias of setcps).' },
  setbpm: { args: 'bpm?: number', global: true, method: false, desc: 'Set the tempo in beats per minute.' },
  setDefaultVoicings: { args: "mode?: string", global: true, method: false, desc: 'Set the default voicing dictionary, e.g. setDefaultVoicings("legacy").' },
  all: { args: 'fn: (pat: Pattern) => Pattern', global: true, method: false, desc: 'Apply a function to all currently playing patterns (REPL global).' },
  bytebeat: { args: 'expr: string | number | Pattern', global: true, method: true, desc: 'Bytebeat synthesis from an integer expression.' },
  _punchcard: { args: 'options?: any', global: false, method: true, desc: 'Draw a punchcard of the pattern. Does not change the audio.' },
  _pianoroll: { args: 'options?: any', global: false, method: true, desc: 'Draw a pianoroll of the pattern. Does not change the audio.' },
  _scope: { args: 'options?: any', global: false, method: true, desc: 'Draw an oscilloscope. Does not change the audio.' },
  _spectrum: { args: 'options?: any', global: false, method: true, desc: 'Draw a spectrum analyser. Does not change the audio.' },
  _pitchwheel: { args: 'options?: any', global: false, method: true, desc: 'Draw a pitchwheel. Does not change the audio.' },
};
