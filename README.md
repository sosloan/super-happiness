# Ada Thoughts Hono API

A small Hono service for Ada Lovelace-inspired typed thoughts, the 73 Ada
reserved words, their definitions and relations, and the companion feed.

## Run

Requires Node.js 20 or newer.

```sh
npm install
npm start
```

The server listens on port `3000` by default. Set `PORT` to use another port.

## Endpoints

- `GET /` — service name and endpoint list
- `GET /thoughts` and `GET /thoughts/:index` — canonical thoughts and indexed lookup
- `POST /thoughts` — create a validated thought (`kind`, `symbols`, `pattern`, `value`)
- `GET /keywords`, `GET /keywords/:word`, and `GET /keywords/index/:index` — definitions and lookup
- `GET /feed` — generated keywords, definitions, relations, thoughts, and links
- `POST /calculate` — apply `add`, `subtract`, `multiply`, `rem`, `mod`, or `delay`
- `POST /differences` — calculate adjacent differences for a numeric `series`
- `POST /reverse` — return a reversed `series`

Invalid input returns a JSON error response. Null thought values and operands
are rejected rather than silently accepted.

## Test

```sh
npm test
```
