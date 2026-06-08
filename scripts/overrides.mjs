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
