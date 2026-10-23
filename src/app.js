import { Hono } from "hono";
import {
  abstractThought,
  bernoulliDifferences,
  buildFeed,
  KEYWORDS,
  keyword,
  reverseSequence,
  selectMethod,
  THOUGHTS,
  thoughtAt,
} from "./ada-thoughts.js";

export const app = new Hono();

app.get("/", (c) => c.json({
  name: "Ada Thoughts",
  endpoints: ["/thoughts", "/thoughts/:index", "/keywords", "/keywords/:word", "/feed"],
}));

app.get("/thoughts", (c) => c.json(THOUGHTS));

app.get("/thoughts/:index", (c) => {
  const indexText = c.req.param("index");
  if (!/^(0|[1-9]\d*)$/.test(indexText)) {
    return c.json({ error: "thought index must be a non-negative integer" }, 400);
  }
  try {
    return c.json(thoughtAt(Number(indexText)));
  } catch {
    return c.json({ error: "thought not found" }, 404);
  }
});

app.get("/keywords", (c) => c.json(KEYWORDS));

app.get("/keywords/:word", (c) => {
  try {
    return c.json(keyword(c.req.param("word")));
  } catch {
    return c.json({ error: "keyword not found" }, 404);
  }
});

app.get("/feed", (c) => c.json(buildFeed()));

app.post("/thoughts", async (c) => {
  try {
    const thought = abstractThought(await c.req.json());
    return c.json(thought, 201);
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "invalid thought" }, 400);
  }
});

app.post("/calculate", async (c) => {
  try {
    const { op, left, right } = await c.req.json();
    if (![left, right].every((value) => typeof value === "number" && Number.isFinite(value))) {
      return c.json({ error: "operands must be finite numbers" }, 400);
    }
    const result = selectMethod(op, left, right);
    if (typeof result === "number" && !Number.isFinite(result)) {
      return c.json({ error: "result must be finite" }, 400);
    }
    return c.json({ result });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "invalid calculation" }, 400);
  }
});

app.post("/differences", async (c) => {
  try {
    const { series } = await c.req.json();
    if (!Array.isArray(series) || !series.every(Number.isFinite)) {
      return c.json({ error: "series must contain only finite numbers" }, 400);
    }
    return c.json({ differences: bernoulliDifferences(series) });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "invalid series" }, 400);
  }
});

app.post("/reverse", async (c) => {
  try {
    const { series } = await c.req.json();
    if (!Array.isArray(series)) return c.json({ error: "series must be an array" }, 400);
    return c.json({ series: reverseSequence(series) });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "invalid series" }, 400);
  }
});
