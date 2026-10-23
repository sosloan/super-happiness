@ Market exchange. Tick = 1 penny. VAT rate = 1 penny.
@
@ Tools (fpp-tools is already indexed; NASA fpp ships the translators):
@   fpp-check     Market/Market.fpp              validate semantics
@   fpp-format    Market/Market.fpp              pretty-print
@   fpp-diagram --kind state-machine --name Market.MatchSm Market/Market.fpp
@   fpp-diagram --kind topology --name Market.MarketFixed  Market/Market.fpp
@   fpp-diagram --kind topology --name Market.MarketBarter Market/Market.fpp
@   fpp-diagram --kind connection-group --name Market.MarketFixed.Fixed
@   fpp-to-layout Market/Market.fpp              then fpl-layout / fpl-write-eps
@   fpp-to-cpp    Market/Market.fpp              C++ stubs around the asm
@
@ Plumbing: Book posts a price band. Matcher intersects ranges on the barter
@ path. Clearing is the range-rate gate plus the 1-penny levy. Wallet settles.
@ Primitive goods and band sequences live in FppTest.Market / FppTest.SmMarket.

module Market {

  @ One penny. Every price is a whole number of ticks.
  constant TICK = 1

  @ The VAT rate is one penny: a flat exchange levy, not a percentage.
  constant VAT_RATE = 1

  @ Legal rate range. 0 = zero-rated band, 1 = the levy.
  constant RATE_MIN = 0
  constant RATE_MAX = 1

  @ Posted book. Below PRICE_MIN the 1p levy cannot be collected.
  constant PRICE_MIN = 1
  constant PRICE_MAX = 2147483647

  @ Haggle is bounded so the matcher always terminates.
  constant MAX_ROUNDS = 8
  constant CONCESSION_SHIFT = 3

  enum Outcome {
    SOLD
    WALKED
    NO_FUNDS
    OUT_OF_RANGE
  }

  @ Posted tax band: the 1p rate applies only inside [lo, hi].
  struct Band {
    lo: U32
    hi: U32
    rate: U32
  }

  @ One fill, three ways. net + vat == gross always holds.
  struct Quote {
    net: U32
    vat: U32
    gross: U32
    rate: U32
    lo: U32
    hi: U32
  }

  @ What the match window cost and what it saved against the sticker.
  struct Fill {
    ask: U32
    offer: U32
    matchLo: U32
    matchHi: U32
    rounds: U32
    saved: U32
  }

  @ Pick up a book and name the band you are shopping in.
  port Browse(
    isbn: U32
    band: Band
  )

  @ Posted ask. Used only on the fixed-price path.
  port Post(
    list: U32
    band: Band
  )

  @ Buyer names a number, in pennies, on-tick.
  port Offer(
    gross: U32
  )

  @ Seller names a number back. final is true when the window has closed.
  port Counter(
    gross: U32
    final: bool
  )

  @ Range-rate gate: is this price in the band with a legal rate?
  port InRange(
    price: U32
    band: Band
  ) -> bool

  @ Collect the 1-penny levy on a fill that already cleared the gate.
  port Levy(
    gross: U32
    band: Band
  ) -> Quote

  @ Push a finished quote to the buyer. Not a call with a return.
  port QuoteOut(
    q: Quote
  )

  @ Reserve funds against the settled gross. Returns what is actually held.
  port Reserve(
    gross: U32
  ) -> U32

  @ End of transaction, whether or not money changed hands.
  port Receipt(
    outcome: Outcome
    q: Quote
    f: Fill
  )

  @ Posted-price stall. Quote, pay, or walk. The interesting work is the gate.
  state machine StallSm {

    action quoteHw
    action sell
    action refuse

    signal browse
    signal accept
    signal decline
    signal short
    signal oob

    initial enter BROWSING

    state BROWSING {
      on browse do { quoteHw } enter QUOTED
    }

    state QUOTED {
      on accept do { sell } enter BROWSING
      on decline enter BROWSING
      on short do { refuse } enter BROWSING
      on oob do { refuse } enter BROWSING
    }

  }

  @ Matching engine. HAGGLING is re-entered per round and leaves only when
  @ the three ranges close, the window is empty, or rounds run out.
  state machine MatchSm {

    action openWindow
    action concede
    action settle
    action walkAway

    signal browse
    signal offer
    signal converged
    signal empty
    signal exhausted
    signal decline

    initial enter BROWSING

    state BROWSING {
      on browse do { openWindow } enter HAGGLING
    }

    state HAGGLING {
      on offer do { concede }
      on converged do { settle } enter SETTLED
      on empty do { walkAway } enter BROWSING
      on exhausted do { walkAway } enter BROWSING
      on decline do { walkAway } enter BROWSING
    }

    state SETTLED {
      on browse do { openWindow } enter HAGGLING
    }

  }

  @ Posted book: sticker plus the tax band the levy applies inside.
  passive component Book {

    sync input port post: Post
    sync input port browse: Browse
    output port quoteOut: QuoteOut

  }

  @ Range-rate gate and 1-penny levy. Wraps MarketFixed.asm.
  passive component Clearing {

    sync input port inRange: InRange
    sync input port levy: Levy
    output port quoteOut: QuoteOut

  }

  @ Matching engine. Wraps MarketBarter.asm. Intersects seller, buyer, band.
  active component Matcher {

    sync input port open: Browse
    async input port offer: Offer

    output port counter: Counter
    output port levy: Levy

    state machine instance sm: MatchSm

  }

  @ Holds the money and is the only thing allowed to say no on funds.
  passive component Wallet {

    sync input port reserve: Reserve
    output port receipt: Receipt

  }

  @ Front of house. Queued because offers arrive one at a time.
  queued component Stall {

    sync input port browse: Browse
    async input port offer: Offer

    output port post: Post
    output port priceIt: Browse
    output port offerOut: Offer
    output port inRange: InRange
    output port levy: Levy
    output port counter: Counter
    output port reserve: Reserve

    state machine instance sm: StallSm

  }

  active component Buyer {

    async input port quoteIn: QuoteOut
    async input port counterIn: Counter
    async input port receipt: Receipt

    output port browse: Browse
    output port offer: Offer

  }

  instance buyer: Buyer base id 0x0100 \
    queue size 10 \
    stack size 4096 \
    priority 90

  instance stall: Stall base id 0x0200 \
    queue size 10

  instance book: Book base id 0x0300

  instance clearing: Clearing base id 0x0400

  instance wallet: Wallet base id 0x0500

  instance matcher: Matcher base id 0x0600 \
    queue size 10 \
    stack size 4096 \
    priority 80

  @ No haggling: posted price through the range-rate gate and out.
  topology MarketFixed {

    instance buyer
    instance stall
    instance book
    instance clearing
    instance wallet

    connections Fixed {
      buyer.browse     -> stall.browse
      stall.post       -> book.post
      stall.priceIt    -> book.browse
      stall.inRange    -> clearing.inRange
      stall.levy       -> clearing.levy
      clearing.quoteOut -> buyer.quoteIn
      stall.reserve    -> wallet.reserve
      wallet.receipt   -> buyer.receipt
    }

  }

  @ Haggling: matcher sits on the loop, clearing taxes the fill.
  topology MarketBarter {

    instance buyer
    instance stall
    instance matcher
    instance clearing
    instance wallet

    connections Barter {
      buyer.browse      -> stall.browse
      stall.priceIt     -> matcher.open
      buyer.offer        -> stall.offer
      stall.offerOut     -> matcher.offer
      matcher.counter    -> buyer.counterIn
      matcher.levy       -> clearing.levy
      stall.inRange      -> clearing.inRange
      clearing.quoteOut -> buyer.quoteIn
      stall.reserve     -> wallet.reserve
      wallet.receipt    -> buyer.receipt
    }

  }

}
