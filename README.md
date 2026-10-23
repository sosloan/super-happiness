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
