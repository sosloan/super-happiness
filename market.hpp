/* Market.fpp host types.
 *
 * Tick and levy are one penny. Clearing is the range-rate gate. The matcher
 * intersects seller, buyer, and tax band. Fills are submitted to the global
 * orderbook in hft_orderbook.asm (one venue per process).
 */
#ifndef MARKET_HPP
#define MARKET_HPP

#include "orderbook.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace market {

constexpr uint32_t TICK = 1;
constexpr uint32_t VAT_RATE = 1;
constexpr uint32_t RATE_MIN = 0;
constexpr uint32_t RATE_MAX = 1;
constexpr uint32_t PRICE_MIN = 1;
constexpr uint32_t PRICE_MAX = 2147483647u;
constexpr uint32_t MAX_ROUNDS = 8;
constexpr uint32_t CONCESSION_SHIFT = 3;

enum class Outcome { Sold, Walked, NoFunds, OutOfRange };

enum class StallState { Browsing, Quoted };

enum class MatchState { Browsing, Haggling, Settled };

struct Band {
    uint32_t lo;
    uint32_t hi;
    uint32_t rate;
};

struct Quote {
    uint32_t net;
    uint32_t vat;
    uint32_t gross;
    uint32_t rate;
    uint32_t lo;
    uint32_t hi;
};

struct Fill {
    uint32_t ask;
    uint32_t offer;
    uint32_t match_lo;
    uint32_t match_hi;
    uint32_t rounds;
    uint32_t saved;
};

struct Listing {
    uint32_t isbn;
    uint32_t list;
    Band band;
    uint32_t qty;
};

struct Receipt {
    Outcome outcome;
    Quote quote;
    Fill fill;
    ObMatchingResult match;
    StallState stall;
    MatchState matcher;
};

bool band_legal(Band band);
bool in_range(uint32_t price, Band band);
std::optional<Quote> levy(uint32_t gross, Band band);

const char *outcome_name(Outcome outcome);

class Book {
  public:
    void post(Listing listing);
    const Listing *browse(uint32_t isbn) const;
    bool take(uint32_t isbn);

  private:
    std::vector<Listing> listings_;
};

class Wallet {
  public:
    explicit Wallet(uint32_t balance);
    uint32_t balance() const;
    uint32_t reserve(uint32_t gross);
    void credit(uint32_t gross);

  private:
    uint32_t balance_;
};

/* Single global book. reset() rebuilds the assembly free list. */
class Venue {
  public:
    Venue();
    void reset();
    uint32_t rest(uint64_t id, uint8_t side, uint32_t pennies, uint32_t qty);
    ObMatchingResult cross(uint64_t id, uint8_t side, uint32_t pennies, uint32_t qty);
    bool cancel(uint64_t id);
};

class Matcher {
  public:
    Matcher();
    std::optional<Fill> haggle(uint32_t ask, uint32_t offer, Band band, bool decline);
    MatchState state() const;

  private:
    MatchState state_;
};

class Stall {
  public:
    Stall();
    Receipt fixed(const Listing &listing, Wallet &wallet, Venue &venue, bool accept);
    Receipt barter(const Listing &listing, uint32_t offer, Wallet &wallet, Venue &venue,
                   Matcher &matcher, bool decline);

  private:
    StallState state_;
    uint64_t ids_;
    Receipt settle(const Listing &listing, Quote quote, Fill fill, Wallet &wallet, Venue &venue,
                   MatchState matcher_state);
};

class Exchange {
  public:
    explicit Exchange(uint32_t buyer_funds);
    void list(Listing listing);
    Receipt fixed(uint32_t isbn, bool accept);
    Receipt barter(uint32_t isbn, uint32_t offer, bool decline);
    uint32_t balance() const;

  private:
    Book book_;
    Wallet wallet_;
    Venue venue_;
    Matcher matcher_;
    Stall stall_;
};

} /* namespace market */

#endif
