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
# super-happiness

Market exchange host. [`Market.fpp`](Market.fpp) is the model: one-penny tick, one-penny levy, posted-price stall (`MarketFixed`) and bounded haggle (`MarketBarter`). [`hft_orderbook.asm`](hft_orderbook.asm) is the x86-64 matching engine those fills are sent to.

`main` is the application. Clearing, wallet, stall, and matcher follow the FPP ports. A sale rests a limit and crosses it through `ob_add_order`.

## Build

Requires `nasm` and `g++`.

```
make
./market
```

`make test` builds and runs the host. `make standalone` assembles the orderbook's own `_start` demo (`ld`, no libc). The host link renames that symbol so the C++ runtime owns process entry.
