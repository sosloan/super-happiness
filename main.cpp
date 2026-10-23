/* Market host.
 *
 * Market.fpp names the exchange (1p tick, 1p levy, fixed and barter).
 * hft_orderbook.asm is the price-time venue those fills are sent to.
 */
#include "market.hpp"
#include "orderbook.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

int g_failures = 0;

void expect(bool ok, const std::string &what) {
    if (!ok) {
        std::cerr << "  FAIL " << what << "\n";
        ++g_failures;
    }
}

bool near(double value, double want) { return std::fabs(value - want) < 1e-6; }

const char *status_name(uint32_t status) {
    switch (status) {
    case OB_STATUS_PENDING:
        return "PENDING";
    case OB_STATUS_FILLED:
        return "FILLED";
    case OB_STATUS_PARTIAL:
        return "PARTIAL";
    case OB_STATUS_REJECTED:
        return "REJECTED";
    default:
        return "?";
    }
}

void print_receipt(const char *path, const market::Receipt &receipt, uint32_t wallet) {
    std::cout << "  " << path << " " << market::outcome_name(receipt.outcome);
    if (receipt.quote.gross != 0 || receipt.outcome == market::Outcome::Sold) {
        std::cout << "  net=" << receipt.quote.net << " vat=" << receipt.quote.vat
                  << " gross=" << receipt.quote.gross;
    }
    if (receipt.fill.rounds != 0 || receipt.fill.saved != 0) {
        std::cout << "  rounds=" << receipt.fill.rounds << " saved=" << receipt.fill.saved
                  << " px=" << receipt.fill.match_lo;
    }
    if (receipt.outcome == market::Outcome::Sold) {
        std::cout << "  book=" << status_name(receipt.match.status)
                  << " qty=" << receipt.match.filled_qty
                  << " avg=" << static_cast<uint64_t>(receipt.match.avg_price + 0.5);
    }
    std::cout << "  wallet=" << wallet << "\n";
}

void check_identity(const market::Receipt &receipt) {
    if (receipt.outcome != market::Outcome::Sold && receipt.outcome != market::Outcome::Walked) {
        return;
    }
    if (receipt.quote.gross == 0) {
        return;
    }
    expect(receipt.quote.net + receipt.quote.vat == receipt.quote.gross, "net + vat == gross");
    expect(receipt.quote.vat == 0 || receipt.quote.vat == market::VAT_RATE, "levy is 0 or 1 penny");
}

int engine_demo() {
    std::cout << "[engine] hft_orderbook.asm\n";
    ob_init();

    ObOrder bid{};
    bid.id_lo = 0xA1;
    bid.price = 15000.0;
    bid.quantity = 100;
    bid.side = OB_SIDE_BUY;
    bid.type = OB_TYPE_LIMIT;
    bid.tif = OB_TIF_GTC;
    bid.priority = 1;
    bid.next_idx = OB_FREE_SENTINEL;

    ObOrder ask{};
    ask.id_lo = 0xB2;
    ask.price = 15050.0;
    ask.quantity = 100;
    ask.side = OB_SIDE_SELL;
    ask.type = OB_TYPE_LIMIT;
    ask.tif = OB_TIF_GTC;
    ask.priority = 1;
    ask.next_idx = OB_FREE_SENTINEL;

    ObMatchingResult result{};
    ObExecution execs[OB_MAX_EXECUTIONS]{};
    const uint32_t bid_idx = ob_add_order(&bid, &result, execs);
    const uint32_t ask_idx = ob_add_order(&ask, &result, execs);
    expect(bid_idx != OB_FREE_SENTINEL && ask_idx != OB_FREE_SENTINEL, "rest bid and ask");

    const double best_bid = ob_best_bid();
    const double best_ask = ob_best_ask();
    const double spread = ob_spread();
    const double mid = ob_mid_price();
    const double bps = ob_spread_bps();
    std::cout << "  bid=" << best_bid << " ask=" << best_ask << " spread=" << spread
              << " mid=" << mid << " bps=" << bps << "\n";
    expect(near(best_bid, 15000.0), "best bid");
    expect(near(best_ask, 15050.0), "best ask");
    expect(near(spread, 50.0), "spread");
    expect(near(mid, 15025.0), "mid");
    expect(near(bps, (50.0 / 15000.0) * 10000.0), "spread bps");

    ObOrder buy{};
    buy.id_lo = 0xC3;
    buy.price = 15050.0;
    buy.quantity = 50;
    buy.side = OB_SIDE_BUY;
    buy.type = OB_TYPE_LIMIT;
    buy.tif = OB_TIF_IOC;
    buy.priority = 1;
    buy.next_idx = OB_FREE_SENTINEL;
    ObMatchingResult fill{};
    ob_add_order(&buy, &fill, execs);
    std::cout << "  take 50 @ 15050 -> " << status_name(fill.status)
              << " qty=" << fill.filled_qty << " avg=" << fill.avg_price << "\n";
    expect(fill.status == OB_STATUS_FILLED && fill.filled_qty == 50, "ioc fill");
    expect(near(fill.avg_price, 15050.0), "fill price");
    expect(near(ob_best_ask(), 15050.0), "residual ask");

    expect(ob_cancel_order(0xB2, 0) == 1, "cancel ask");
    expect(std::isnan(ob_best_ask()), "ask gone");
    expect(ob_cancel_order(0xB2, 0) == 0, "cancel miss");
    return 0;
}

void check_sold(const market::Receipt &receipt, uint32_t gross, uint32_t vat) {
    expect(receipt.outcome == market::Outcome::Sold, "sold");
    expect(receipt.quote.gross == gross && receipt.quote.vat == vat, "quote");
    expect(receipt.quote.net + receipt.quote.vat == receipt.quote.gross, "identity");
    expect(receipt.match.status == OB_STATUS_FILLED && receipt.match.filled_qty == 1, "venue fill");
    expect(near(receipt.match.avg_price, static_cast<double>(gross)), "venue price");
    expect(receipt.stall == market::StallState::Browsing, "stall reset");
}

} /* namespace */

int main() {
    std::cout << std::unitbuf;
    std::cout << "=== Market host  tick=" << market::TICK << "p  levy=" << market::VAT_RATE
              << "p ===\n";

    engine_demo();
    ob_init();

    {
        std::cout << "[fixed] MarketFixed  isbn=1001 list=2500 band=[2000,3000] rate=1\n";
        market::Exchange ex(10000);
        ex.list({1001, 2500, {2000, 3000, 1}, 2});
        const market::Receipt sold = ex.fixed(1001, true);
        print_receipt("accept", sold, ex.balance());
        check_sold(sold, 2500, 1);
        expect(ex.balance() == 7500, "wallet debited");
        expect(sold.fill.saved == 0, "no haggle on the posted path");

        const market::Receipt declined = ex.fixed(1001, false);
        print_receipt("decline", declined, ex.balance());
        expect(declined.outcome == market::Outcome::Walked, "decline walks");
        expect(ex.balance() == 7500, "decline does not charge");
    }

    {
        std::cout << "[fixed] list outside the band\n";
        market::Exchange ex(10000);
        ex.list({1002, 1500, {2000, 3000, 1}, 1});
        const market::Receipt oob = ex.fixed(1002, true);
        print_receipt("oob", oob, ex.balance());
        expect(oob.outcome == market::Outcome::OutOfRange, "gate refuses");
        expect(ex.balance() == 10000, "oob does not charge");
    }

    {
        std::cout << "[fixed] wallet short of the levy-inclusive gross\n";
        market::Exchange ex(100);
        ex.list({1003, 2500, {2000, 3000, 1}, 1});
        const market::Receipt shortfall = ex.fixed(1003, true);
        print_receipt("short", shortfall, ex.balance());
        expect(shortfall.outcome == market::Outcome::NoFunds, "wallet is the only funds refusal");
        expect(ex.balance() == 100, "short does not debit");
    }

    {
        std::cout << "[barter] MarketBarter  ask=1000 offer=980 band=[900,1100] rate=1\n";
        market::Exchange ex(5000);
        ex.list({2001, 1000, {900, 1100, 1}, 1});
        const market::Receipt sold = ex.barter(2001, 980, false);
        print_receipt("haggle", sold, ex.balance());
        check_sold(sold, 990, 1);
        expect(sold.fill.rounds == 8, "closes on the last concession round");
        expect(sold.fill.saved == 10, "saved against the sticker");
        expect(sold.matcher == market::MatchState::Settled, "matcher settled");
        expect(ex.balance() == 4010, "barter debit");
        check_identity(sold);
    }

    {
        std::cout << "[barter] zero-rated band, buyer already through the sticker\n";
        market::Exchange ex(5000);
        ex.list({2002, 800, {100, 2000, 0}, 1});
        const market::Receipt sold = ex.barter(2002, 900, false);
        print_receipt("cross", sold, ex.balance());
        check_sold(sold, 800, 0);
        expect(sold.fill.rounds == 0 && sold.fill.saved == 0, "no concession needed");
        expect(ex.balance() == 4200, "zero-rated debit");
    }

    {
        std::cout << "[barter] gap does not close in " << market::MAX_ROUNDS << " rounds\n";
        market::Exchange ex(5000);
        ex.list({2003, 1000, {1, 5000, 1}, 1});
        const market::Receipt walked = ex.barter(2003, 100, false);
        print_receipt("exhaust", walked, ex.balance());
        expect(walked.outcome == market::Outcome::Walked, "exhausted window");
        expect(ex.balance() == 5000, "walk does not charge");
    }

    {
        std::cout << "[barter] illegal rate\n";
        market::Exchange ex(5000);
        ex.list({2004, 1000, {1, 5000, 5}, 1});
        const market::Receipt bad = ex.barter(2004, 990, false);
        print_receipt("rate", bad, ex.balance());
        expect(bad.outcome == market::Outcome::OutOfRange, "rate gate");
    }

    if (g_failures != 0) {
        std::cerr << g_failures << " check(s) failed\n";
        return 1;
    }
    std::cout << "market: all checks passed\n";
    return 0;
}
