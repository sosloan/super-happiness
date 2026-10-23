#include "market.hpp"

namespace market {

bool band_legal(Band band) {
    return band.rate >= RATE_MIN && band.rate <= RATE_MAX && band.lo <= band.hi &&
           band.lo >= PRICE_MIN && band.hi <= PRICE_MAX;
}

bool in_range(uint32_t price, Band band) {
    if (!band_legal(band)) {
        return false;
    }
    if (price < PRICE_MIN || price > PRICE_MAX || (price % TICK) != 0) {
        return false;
    }
    return price >= band.lo && price <= band.hi;
}

std::optional<Quote> levy(uint32_t gross, Band band) {
    if (!in_range(gross, band)) {
        return std::nullopt;
    }
    Quote quote{};
    quote.gross = gross;
    quote.rate = band.rate;
    quote.lo = band.lo;
    quote.hi = band.hi;
    quote.vat = band.rate == 0 ? 0 : VAT_RATE;
    if (quote.gross < quote.vat) {
        return std::nullopt;
    }
    quote.net = quote.gross - quote.vat;
    return quote;
}

const char *outcome_name(Outcome outcome) {
    switch (outcome) {
    case Outcome::Sold:
        return "SOLD";
    case Outcome::Walked:
        return "WALKED";
    case Outcome::NoFunds:
        return "NO_FUNDS";
    case Outcome::OutOfRange:
        return "OUT_OF_RANGE";
    }
    return "WALKED";
}

void Book::post(Listing listing) { listings_.push_back(listing); }

const Listing *Book::browse(uint32_t isbn) const {
    for (const Listing &listing : listings_) {
        if (listing.isbn == isbn) {
            return &listing;
        }
    }
    return nullptr;
}

bool Book::take(uint32_t isbn) {
    for (Listing &listing : listings_) {
        if (listing.isbn == isbn && listing.qty > 0) {
            --listing.qty;
            return true;
        }
    }
    return false;
}

Wallet::Wallet(uint32_t balance) : balance_(balance) {}

uint32_t Wallet::balance() const { return balance_; }

uint32_t Wallet::reserve(uint32_t gross) {
    if (balance_ < gross) {
        return balance_;
    }
    balance_ -= gross;
    return gross;
}

void Wallet::credit(uint32_t gross) { balance_ += gross; }

Venue::Venue() { reset(); }

void Venue::reset() { ob_init(); }

uint32_t Venue::rest(uint64_t id, uint8_t side, uint32_t pennies, uint32_t qty) {
    ObOrder order{};
    order.id_lo = id;
    order.price = static_cast<double>(pennies);
    order.quantity = qty;
    order.side = side;
    order.type = OB_TYPE_LIMIT;
    order.tif = OB_TIF_GTC;
    order.priority = 1;
    order.next_idx = OB_FREE_SENTINEL;

    ObMatchingResult result{};
    ObExecution execs[OB_MAX_EXECUTIONS]{};
    return ob_add_order(&order, &result, execs);
}

ObMatchingResult Venue::cross(uint64_t id, uint8_t side, uint32_t pennies, uint32_t qty) {
    ObOrder order{};
    order.id_lo = id;
    order.price = static_cast<double>(pennies);
    order.quantity = qty;
    order.side = side;
    order.type = OB_TYPE_LIMIT;
    order.tif = OB_TIF_IOC;
    order.priority = 1;
    order.next_idx = OB_FREE_SENTINEL;

    ObMatchingResult result{};
    ObExecution execs[OB_MAX_EXECUTIONS]{};
    ob_add_order(&order, &result, execs);
    return result;
}

bool Venue::cancel(uint64_t id) { return ob_cancel_order(id, 0) == 1; }

Matcher::Matcher() : state_(MatchState::Browsing) {}

MatchState Matcher::state() const { return state_; }

std::optional<Fill> Matcher::haggle(uint32_t ask, uint32_t offer, Band band, bool decline) {
    state_ = MatchState::Haggling;

    auto walk = [&]() -> std::optional<Fill> {
        state_ = MatchState::Browsing;
        return std::nullopt;
    };

    if (decline || ask < PRICE_MIN || offer < PRICE_MIN) {
        return walk();
    }

    /* Buyer already crossed the sticker inside the tax band. */
    if (offer >= ask && in_range(ask, band)) {
        Fill fill{};
        fill.ask = ask;
        fill.offer = offer;
        fill.match_lo = ask;
        fill.match_hi = ask;
        fill.rounds = 0;
        fill.saved = 0;
        state_ = MatchState::Settled;
        return fill;
    }

    /* Seller only walks down, buyer only walks up. No overlap with the band. */
    if (!band_legal(band) || ask < band.lo || offer > band.hi || offer > ask) {
        return walk();
    }
    const uint32_t feasible_lo = offer > band.lo ? offer : band.lo;
    const uint32_t feasible_hi = ask < band.hi ? ask : band.hi;
    if (feasible_lo > feasible_hi) {
        return walk();
    }

    uint32_t seller = ask;
    uint32_t buyer = offer;
    for (uint32_t round = 1; round <= MAX_ROUNDS; ++round) {
        if (buyer >= seller) {
            break;
        }
        const uint32_t gap = seller - buyer;
        uint32_t step = gap >> CONCESSION_SHIFT;
        if (step < TICK) {
            step = TICK;
        }
        uint32_t seller_give = step > gap ? gap : step;
        uint32_t buyer_give = step;
        if (buyer_give > gap - seller_give) {
            buyer_give = gap - seller_give;
        }
        const uint32_t prev_seller = seller;
        const uint32_t prev_buyer = buyer;
        seller -= seller_give;
        buyer += buyer_give;
        if (seller < band.lo) {
            seller = band.lo;
        }
        if (buyer > band.hi) {
            buyer = band.hi;
        }
        if (seller == prev_seller && buyer == prev_buyer) {
            return walk();
        }
        if (buyer >= seller && in_range(seller, band)) {
            Fill fill{};
            fill.ask = ask;
            fill.offer = offer;
            fill.match_lo = seller;
            fill.match_hi = seller;
            fill.rounds = round;
            fill.saved = ask - seller;
            state_ = MatchState::Settled;
            return fill;
        }
    }

    return walk();
}

Stall::Stall() : state_(StallState::Browsing), ids_(1) {}

Receipt Stall::settle(const Listing &, Quote quote, Fill fill, Wallet &wallet, Venue &venue,
                      MatchState matcher_state) {
    Receipt receipt{};
    receipt.quote = quote;
    receipt.fill = fill;
    receipt.stall = StallState::Quoted;
    receipt.matcher = matcher_state;

    const uint32_t held = wallet.reserve(quote.gross);
    if (held < quote.gross) {
        state_ = StallState::Browsing;
        receipt.stall = state_;
        receipt.outcome = Outcome::NoFunds;
        return receipt;
    }

    const uint64_t sell_id = ids_++;
    const uint64_t buy_id = ids_++;
    const uint32_t rested = venue.rest(sell_id, OB_SIDE_SELL, quote.gross, 1);
    receipt.match = venue.cross(buy_id, OB_SIDE_BUY, quote.gross, 1);
    if (rested == OB_FREE_SENTINEL || receipt.match.status != OB_STATUS_FILLED ||
        receipt.match.filled_qty != 1) {
        wallet.credit(quote.gross);
        if (rested != OB_FREE_SENTINEL) {
            venue.cancel(sell_id);
        }
        state_ = StallState::Browsing;
        receipt.stall = state_;
        receipt.outcome = Outcome::Walked;
        return receipt;
    }

    state_ = StallState::Browsing;
    receipt.stall = state_;
    receipt.matcher = matcher_state;
    receipt.outcome = Outcome::Sold;
    return receipt;
}

Receipt Stall::fixed(const Listing &listing, Wallet &wallet, Venue &venue, bool accept) {
    Receipt receipt{};
    receipt.stall = StallState::Browsing;
    receipt.matcher = MatchState::Browsing;
    receipt.fill.ask = listing.list;
    receipt.fill.offer = listing.list;

    state_ = StallState::Browsing;
    if (listing.qty == 0 || !in_range(listing.list, listing.band)) {
        receipt.outcome = Outcome::OutOfRange;
        return receipt;
    }

    const std::optional<Quote> quote = levy(listing.list, listing.band);
    if (!quote) {
        receipt.outcome = Outcome::OutOfRange;
        return receipt;
    }

    /* browse -> quoteHw -> QUOTED */
    state_ = StallState::Quoted;
    receipt.quote = *quote;
    receipt.fill.match_lo = quote->gross;
    receipt.fill.match_hi = quote->gross;
    if (!accept) {
        state_ = StallState::Browsing;
        receipt.stall = state_;
        receipt.outcome = Outcome::Walked;
        return receipt;
    }
    return settle(listing, *quote, receipt.fill, wallet, venue, MatchState::Browsing);
}

Receipt Stall::barter(const Listing &listing, uint32_t offer, Wallet &wallet, Venue &venue,
                      Matcher &matcher, bool decline) {
    Receipt receipt{};
    receipt.stall = StallState::Browsing;
    receipt.matcher = matcher.state();
    receipt.fill.ask = listing.list;
    receipt.fill.offer = offer;

    if (!band_legal(listing.band) || listing.qty == 0) {
        receipt.outcome = Outcome::OutOfRange;
        receipt.matcher = MatchState::Browsing;
        return receipt;
    }

    state_ = StallState::Quoted;
    const std::optional<Fill> fill = matcher.haggle(listing.list, offer, listing.band, decline);
    receipt.matcher = matcher.state();
    if (!fill) {
        state_ = StallState::Browsing;
        receipt.stall = state_;
        receipt.outcome = Outcome::Walked;
        return receipt;
    }

    receipt.fill = *fill;
    const std::optional<Quote> quote = levy(fill->match_lo, listing.band);
    if (!quote) {
        state_ = StallState::Browsing;
        receipt.stall = state_;
        receipt.outcome = Outcome::OutOfRange;
        return receipt;
    }
    return settle(listing, *quote, *fill, wallet, venue, matcher.state());
}

Exchange::Exchange(uint32_t buyer_funds) : wallet_(buyer_funds) {}

void Exchange::list(Listing listing) { book_.post(listing); }

Receipt Exchange::fixed(uint32_t isbn, bool accept) {
    const Listing *listing = book_.browse(isbn);
    if (listing == nullptr) {
        Receipt missing{};
        missing.outcome = Outcome::Walked;
        return missing;
    }
    Receipt receipt = stall_.fixed(*listing, wallet_, venue_, accept);
    if (receipt.outcome == Outcome::Sold) {
        book_.take(isbn);
    }
    return receipt;
}

Receipt Exchange::barter(uint32_t isbn, uint32_t offer, bool decline) {
    const Listing *listing = book_.browse(isbn);
    if (listing == nullptr) {
        Receipt missing{};
        missing.outcome = Outcome::Walked;
        return missing;
    }
    Receipt receipt = stall_.barter(*listing, offer, wallet_, venue_, matcher_, decline);
    if (receipt.outcome == Outcome::Sold) {
        book_.take(isbn);
    }
    return receipt;
}

uint32_t Exchange::balance() const { return wallet_.balance(); }

} /* namespace market */
