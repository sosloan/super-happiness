export const THOUGHT_KINDS = Object.freeze(["melody", "map", "calculation"]);

export const KEYWORDS = Object.freeze([
  ["abort", "Ada would not abort an inquiry because its first path failed"],
  ["abs", "abs alone did not explain the negative"],
  ["abstract", "able to accept symbols, abstract their patterns, and return a new kind of thought"],
  ["accept", "an engine able to accept symbols"],
  ["access", "access to them would be limited, aliased only with care"],
  ["aliased", "aliased only with care, and never trusted merely because they were new"],
  ["all", "a package of ideas, private at first but meant for all"],
  ["and", "neither and nor or could replace imagination"],
  ["array", "an array of such records, indexed over a range"],
  ["at", "private at first but meant for all"],
  ["begin", "a loop would begin, continue while its condition held, and exit"],
  ["body", "a function in spirit, though the Engine had no body to run it"],
  ["case", "Case by case, it might add, subtract, or multiply"],
  ["constant", "A number was not only a constant"],
  ["declare", "to declare each wheel, column, and card as part of a larger design"],
  ["delay", "elsif the answer required another card, it could delay its work"],
  ["delta", "The delta between two figures was not a mystery; it was a difference the Engine could name"],
  ["digits", "use variables with digits, carry a remainder by rem or mod"],
  ["do", 'instructions might say, "do this," yet a careful pragma would make clear'],
  ["else", "else it could proceed"],
  ["elsif", "elsif the answer required another card, it could delay its work"],
  ["end", "follow rules until it reached the end of a calculation"],
  ["entry", "a protected task might wait at an entry"],
  ["exception", "an exception must not become an excuse for chaos"],
  ["exit", "exit when the work was done"],
  ["for", "private at first but meant for all"],
  ["function", "plan for Bernoulli numbers was a function in spirit"],
  ["generic", "generic enough to serve astronomy or music"],
  ["goto", "or goto the evidence and begin again"],
  ["if", "If the Engine received a question, then it could select a method"],
  ["in", "Some values would be in, others out"],
  ["interface", "an interface might be synchronized"],
  ["is", "nor would she terminate a question before its proof is complete"],
  ["limited", "access to them would be limited"],
  ["loop", "For each operation, a loop would begin"],
  ["mod", "carry a remainder by rem or mod"],
  ["new", "return a new kind of thought"],
  ["not", "did not see a machine that could merely calculate"],
  ["null", "when a result was null, the operator should raise a signal, not hide it"],
  ["of", "a new kind of thought"],
  ["or", "a record of a melody, a map, or a calculation"],
  ["others", "Some values would be in, others out"],
  ["out", "Some values would be in, others out"],
  ["overriding", "no shortcut was overriding the design"],
  ["package", "Her notes were a package of ideas"],
  ["pragma", "a careful pragma would make clear that no shortcut was overriding the design"],
  ["private", "a package of ideas, private at first but meant for all"],
  ["procedure", "altered by procedure rather than accident"],
  ["protected", "a protected task might wait at an entry"],
  ["raise", "the operator should raise a signal, not hide it"],
  ["range", "indexed over a range and altered by procedure rather than accident"],
  ["record", "a record of a melody, a map, or a calculation"],
  ["rem", "carry a remainder by rem or mod"],
  ["renames", "She renames no uncertainty as certainty"],
  ["requeue", "She would requeue the question"],
  ["return", "return a new kind of thought"],
  ["reverse", "reverse a sequence when the cards required it"],
  ["select", "then it could select a method"],
  ["separate", "let separate parts work together without confusing one another"],
  ["some", "Some values would be in, others out"],
  ["subtype", "a subtype could keep each quantity within its proper bounds"],
  ["synchronized", "an interface might be synchronized"],
  ["tagged", "A type might be tagged"],
  ["task", "she began a patient task: to declare each wheel, column, and card"],
  ["terminate", "nor would she terminate a question before its proof is complete"],
  ["then", "If the Engine received a question, then it could select a method"],
  ["type", "A type might be tagged, an interface might be synchronized"],
  ["until", "follow rules until it reached the end of a calculation"],
  ["use", "It would use variables with digits"],
  ["when", "exit when the work was done"],
  ["while", "continue while its condition held"],
  ["with", "With Charles Babbage, she began a patient task"],
  ["xor", "xor did not settle a choice"],
].map(([word, passage], index) => Object.freeze({ word, passage, index })));

export const THOUGHTS = Object.freeze([
  Object.freeze({
    kind: "melody",
    symbols: "Bernoulli sequence cards",
    pattern: "difference-engine recurrence",
    value: "B_n",
  }),
  Object.freeze({
    kind: "map",
    symbols: "wheel · column · card",
    pattern: "declared design of the Analytical Engine",
    value: "larger_design",
  }),
  Object.freeze({
    kind: "calculation",
    symbols: "question → method",
    pattern: "case / elsif / else selection over arithmetic cards",
    value: "named_difference",
  }),
]);

export const DOCTRINE_CLUSTERS = Object.freeze([
  { id: "engine_of_thought", words: ["accept", "abstract", "return", "new", "of"], note: "accept symbols, abstract patterns, return a new kind of thought" },
  { id: "null_doctrine", words: ["null", "raise", "exception", "when"], note: "when null, raise a signal — never hide it" },
  { id: "package_of_ideas", words: ["package", "private", "all", "at", "for"], note: "package of ideas, private at first but meant for all" },
  { id: "protected_bay", words: ["protected", "task", "entry"], note: "protected task waits at an entry" },
  { id: "method_selection", words: ["if", "then", "select", "case", "elsif", "else", "delay"], note: "if/then select; case/elsif delay; else proceed" },
  { id: "loop_lifecycle", words: ["loop", "begin", "while", "exit", "when", "until", "end"], note: "loop begin, while condition, exit when done, until end" },
  { id: "array_of_records", words: ["array", "range", "record", "procedure", "constant"], note: "array of records indexed over a range, altered by procedure" },
  { id: "digit_remainder", words: ["use", "digits", "rem", "mod", "reverse"], note: "use digits; rem or mod; reverse sequence" },
  { id: "parameter_modes", words: ["in", "out", "others", "some", "access", "limited", "aliased"], note: "in/out/others/some; access limited, aliased with care" },
  { id: "typed_interface", words: ["type", "tagged", "interface", "synchronized", "subtype", "generic"], note: "tagged type, synchronized interface, subtype bounds, generic instrument" },
  { id: "design_pragma", words: ["pragma", "do", "overriding"], note: "do this, yet pragma forbids overriding the design" },
  { id: "inquiry_persistence", words: ["abort", "requeue", "goto", "begin", "terminate", "renames", "is"], note: "not abort; requeue or goto evidence; never terminate before proof" },
  { id: "function_spirit", words: ["function", "body"], note: "Bernoulli plan was a function in spirit; Engine had no body" },
  { id: "logic_connectives", words: ["and", "or", "xor", "not", "abs"], note: "and/or/xor/abs cannot replace imagination" },
  { id: "with_babbage", words: ["with", "task", "declare"], note: "With Babbage, began a patient task to declare each part" },
  { id: "separate_parts", words: ["separate"], note: "separate parts work together without confusing one another" },
  { id: "delta_named", words: ["delta"], note: "delta is a difference the Engine could name" },
].map((cluster) => Object.freeze({ ...cluster, words: Object.freeze(cluster.words) })));

export function abstractThought({ kind, symbols, pattern, value }) {
  if (value === null || value === undefined) throw new TypeError("null thought value");
  if (!THOUGHT_KINDS.includes(kind)) throw new TypeError(`unknown kind: ${String(kind)}`);
  if (symbols === null || symbols === undefined || String(symbols).length === 0) {
    throw new TypeError("symbols must be non-empty");
  }
  if (pattern === null || pattern === undefined || String(pattern).length === 0) {
    throw new TypeError("pattern must be non-empty");
  }
  return Object.freeze({ kind, symbols: String(symbols), pattern: String(pattern), value });
}

export function thoughtAt(index) {
  if (!Number.isInteger(index) || index < 0 || index >= THOUGHTS.length) {
    throw new RangeError(`thought index out of range: ${index}`);
  }
  return THOUGHTS[index];
}

export function keywordAt(index) {
  if (!Number.isInteger(index) || index < 0 || index >= KEYWORDS.length) {
    throw new RangeError(`keyword index out of range: ${index}`);
  }
  return KEYWORDS[index];
}

export function keyword(word) {
  const found = KEYWORDS.find((entry) => entry.word === String(word));
  if (!found) throw new RangeError(`unknown reserved word: ${String(word)}`);
  return found;
}

export function selectMethod(op, left, right) {
  if (left === null || left === undefined || right === null || right === undefined) {
    throw new TypeError("null operand");
  }
  switch (op) {
    case "add": return left + right;
    case "subtract": return left - right;
    case "multiply": return left * right;
    case "delay": return null;
    case "rem":
      if (right === 0) throw new RangeError("division by zero");
      return left % right;
    case "mod":
      if (right === 0) throw new RangeError("division by zero");
      return ((left % right) + right) % right;
    default: throw new TypeError(`no method selected for ${String(op)}`);
  }
}

export function bernoulliDifferences(series) {
  if (!Array.isArray(series)) throw new TypeError("null series");
  if (series.length < 2) throw new RangeError("series too short");
  return series.slice(1).map((value, index) => value - series[index]);
}

export function reverseSequence(series) {
  if (!Array.isArray(series)) throw new TypeError("null series");
  return [...series].reverse();
}

export function wordInText(text, word) {
  const escaped = String(word).toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?<![a-z])${escaped}(?![a-z])`, "i").test(String(text));
}

function primaryRelationKind(kinds) {
  if (kinds.includes("shared_definition")) return "shared_definition";
  if (kinds.includes("doctrine")) return "doctrine";
  if (kinds.includes("thought_context")) return "thought_context";
  return "co_mentioned";
}

export function buildFeed() {
  const words = KEYWORDS.map(({ word }) => word);
  const wordSet = new Set(words);
  const definitions = KEYWORDS.map(({ word, passage, index }) => ({
    id: `def:${word}`, keyword: word, index, text: passage,
  }));
  const edgeSet = new Map();
  const addEdge = (a, b, kind, evidence, extra = {}) => {
    const [source, target] = [a, b].sort();
    const key = `${source}::${target}`;
    let edge = edgeSet.get(key);
    if (!edge) {
      edge = { source, target, kinds: [], evidence: [] };
      edgeSet.set(key, edge);
    }
    if (!edge.kinds.includes(kind)) edge.kinds.push(kind);
    if (evidence && !edge.evidence.includes(evidence)) edge.evidence.push(evidence);
    Object.assign(edge, extra);
  };

  for (const { word, passage } of KEYWORDS) {
    for (const other of words) {
      if (other !== word && wordInText(passage, other)) {
        addEdge(word, other, "co_mentioned", `definition of ${word}`);
      }
    }
  }

  const passages = new Map();
  for (const entry of KEYWORDS) {
    const group = passages.get(entry.passage) ?? [];
    group.push(entry);
    passages.set(entry.passage, group);
  }
  for (const [passage, entries] of passages) {
    for (let i = 0; i < entries.length; i += 1) {
      for (let j = i + 1; j < entries.length; j += 1) {
        addEdge(entries[i].word, entries[j].word, "shared_definition", passage, { definition: passage });
      }
    }
  }

  for (const cluster of DOCTRINE_CLUSTERS) {
    const present = cluster.words.filter((word) => wordSet.has(word));
    for (let i = 0; i < present.length; i += 1) {
      for (let j = i + 1; j < present.length; j += 1) {
        addEdge(present[i], present[j], "doctrine", cluster.note, { cluster: cluster.id });
      }
    }
  }

  const thoughts = THOUGHTS.map((thought, index) => {
    const blob = [thought.kind, thought.symbols, thought.pattern, thought.value].join(" ");
    const related = words.filter((word) => wordInText(blob, word));
    related.push("record", "or", "constant");
    return {
      id: `thought:${thought.kind}`,
      index,
      ...thought,
      related_keywords: [...new Set(related)].sort(),
    };
  });

  for (const thought of thoughts) {
    const related = thought.related_keywords;
    for (let i = 0; i < related.length; i += 1) {
      for (let j = i + 1; j < related.length; j += 1) {
        if (wordSet.has(related[i]) && wordSet.has(related[j])) {
          addEdge(related[i], related[j], "thought_context", thought.id, { thought: thought.id });
        }
      }
    }
  }

  const relations = [...edgeSet.values()].map((edge) => {
    edge.kinds.sort();
    edge.evidence = [...new Set(edge.evidence)];
    edge.kind = primaryRelationKind(edge.kinds);
    return edge;
  }).sort((a, b) => a.source.localeCompare(b.source) || a.target.localeCompare(b.target));
  const relationIndex = new Map(words.map((word) => [word, []]));
  for (const edge of relations) {
    relationIndex.get(edge.source).push(edge);
    relationIndex.get(edge.target).push(edge);
  }

  const keywords = KEYWORDS.map(({ word, passage, index }) => {
    const neighboring = new Map();
    for (const edge of relationIndex.get(word)) {
      const other = edge.source === word ? edge.target : edge.source;
      const kinds = neighboring.get(other) ?? new Set();
      edge.kinds.forEach((kind) => kinds.add(kind));
      neighboring.set(other, kinds);
    }
    const related = [...neighboring].map(([other, kinds]) => {
      const sortedKinds = [...kinds].sort();
      return { keyword: other, kind: primaryRelationKind(sortedKinds), kinds: sortedKinds };
    }).sort((a, b) => a.keyword.localeCompare(b.keyword));
    return {
      id: word,
      index,
      keyword: word,
      definition_id: `def:${word}`,
      definition: passage,
      relations: related,
    };
  });

  const thoughtLinks = thoughts.flatMap((thought) => thought.related_keywords.map((word) => ({
    source: word,
    target: thought.id,
    kind: "keyword_to_thought",
  }))).sort((a, b) => a.source.localeCompare(b.source) || a.target.localeCompare(b.target));

  return {
    feed: "Ada-Feed",
    version: "1.0",
    title: "Ada Lovelace Keyword Feed",
    description: "Keywords, definitions, and relations generated from the Ada thoughts package.",
    source: {
      module: "AdaThoughts",
      javascript: "src/ada-thoughts.js",
      prose: "ada-reserved-words.txt",
      companion_index: "writeups/ada-reserved-words.json",
    },
    counts: {
      keywords: keywords.length,
      definitions: definitions.length,
      relations: relations.length,
      thoughts: thoughts.length,
      thought_links: thoughtLinks.length,
      doctrine_clusters: DOCTRINE_CLUSTERS.length,
    },
    thought_kinds: [...THOUGHT_KINDS],
    doctrine_clusters: DOCTRINE_CLUSTERS.map((cluster) => ({
      id: cluster.id,
      keywords: cluster.words.filter((word) => wordSet.has(word)),
      note: cluster.note,
    })),
    keywords,
    definitions,
    relations,
    thoughts,
    thought_links: thoughtLinks,
  };
}

export function selfCheck() {
  if (KEYWORDS.length !== 73 || new Set(KEYWORDS.map(({ word }) => word)).size !== KEYWORDS.length) {
    throw new Error("keyword count or uniqueness check failed");
  }
  if (THOUGHT_KINDS.some((kind) => !THOUGHTS.some((thought) => thought.kind === kind))) {
    throw new Error("thought kinds incomplete");
  }
  for (const { word, passage } of KEYWORDS) {
    if (!["at", "for", "of", "is", "in", "or"].includes(word) && !wordInText(passage, word)) {
      throw new Error(`passage for ${word} lacks the word`);
    }
  }
  if (selectMethod("add", 2, 3) !== 5 || selectMethod("rem", 11, 4) !== 3
    || selectMethod("mod", -11, 4) !== 1) {
    throw new Error("arithmetic check failed");
  }
  if (JSON.stringify(bernoulliDifferences([1, 2, 4, 7])) !== "[1,2,3]"
    || JSON.stringify(reverseSequence([1, 2, 3])) !== "[3,2,1]") {
    throw new Error("sequence check failed");
  }
  if (keyword("record").word !== "record" || thoughtAt(0).kind !== "melody") {
    throw new Error("lookup check failed");
  }
  return true;
}
