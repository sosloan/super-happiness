import test from "node:test";
import assert from "node:assert/strict";
import { app } from "../src/app.js";
import {
  abstractThought,
  buildFeed,
  KEYWORDS,
  selectMethod,
  selfCheck,
} from "../src/ada-thoughts.js";

test("serves the three canonical thoughts and all reserved words", async () => {
  const thoughtsResponse = await app.request("/thoughts");
  assert.equal(thoughtsResponse.status, 200);
  assert.equal((await thoughtsResponse.json()).length, 3);

  const keywordsResponse = await app.request("/keywords");
  assert.equal(keywordsResponse.status, 200);
  const keywords = await keywordsResponse.json();
  assert.equal(keywords.length, 73);
  assert.equal(keywords.at(-1).word, "xor");
  assert.equal(KEYWORDS[0].word, "abort");
});

test("looks up thoughts and keywords with explicit not-found responses", async () => {
  assert.equal((await app.request("/thoughts/0")).status, 200);
  assert.equal((await app.request("/thoughts/nope")).status, 400);
  assert.equal((await app.request("/thoughts/3")).status, 404);
  assert.equal((await app.request("/keywords/record")).status, 200);
  assert.equal((await app.request("/keywords/unknown")).status, 404);
});

test("feed includes matching keyword, definition, thought, and relation counts", async () => {
  const response = await app.request("/feed");
  assert.equal(response.status, 200);
  const feed = await response.json();
  assert.equal(feed.counts.keywords, 73);
  assert.equal(feed.counts.definitions, 73);
  assert.equal(feed.counts.thoughts, 3);
  assert.equal(feed.keywords.length, feed.counts.keywords);
  assert.equal(feed.definitions.length, feed.counts.definitions);
  assert.ok(feed.relations.length > 0);
  assert.ok(feed.thought_links.length > 0);
  assert.equal(feed.relations.find((relation) => relation.source === "record" && relation.target === "return"), undefined);
});

test("creates typed thoughts and rejects null values", async () => {
  const response = await app.request("/thoughts", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ kind: "map", symbols: "wheel", pattern: "design", value: "engine" }),
  });
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), {
    kind: "map", symbols: "wheel", pattern: "design", value: "engine",
  });

  const invalid = await app.request("/thoughts", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ kind: "map", symbols: "wheel", pattern: "design", value: null }),
  });
  assert.equal(invalid.status, 400);
});

test("preserves arithmetic and sequence behavior while validating request data", async () => {
  assert.equal(selectMethod("mod", -11, 4), 1);
  assert.equal(selectMethod("delay", 2, 3), null);
  assert.throws(() => abstractThought({ kind: "melody", symbols: "x", pattern: "y", value: null }));
  assert.equal(selfCheck(), true);

  const calculation = await app.request("/calculate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ op: "add", left: 2, right: 3 }),
  });
  assert.deepEqual(await calculation.json(), { result: 5 });

  const invalid = await app.request("/calculate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ op: "add", left: 2, right: null }),
  });
  assert.equal(invalid.status, 400);

  const differences = await app.request("/differences", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ series: [1, 2, 4, 7] }),
  });
  assert.deepEqual(await differences.json(), { differences: [1, 2, 3] });
});

test("feed generation is deterministic", () => {
  assert.deepEqual(buildFeed(), buildFeed());
});
