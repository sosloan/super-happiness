/* C ABI for hft_orderbook.asm (System V AMD64).
 *
 * The assembly image also exports _start for its standalone demo. The host
 * build renames that symbol so this translation unit can own process entry.
 * Layout must match the comments at the top of hft_orderbook.asm.
 */
#ifndef ORDERBOOK_H
#define ORDERBOOK_H

#include <stddef.h>
#include <stdint.h>

#define OB_SIDE_BUY 0
#define OB_SIDE_SELL 1

#define OB_TYPE_MARKET 0
#define OB_TYPE_LIMIT 1
#define OB_TYPE_STOP 2
#define OB_TYPE_STOP_LIMIT 3
#define OB_TYPE_ICEBERG 4

#define OB_TIF_GTC 0
#define OB_TIF_IOC 1
#define OB_TIF_FOK 2
#define OB_TIF_DAY 3

#define OB_STATUS_PENDING 0
#define OB_STATUS_FILLED 1
#define OB_STATUS_PARTIAL 2
#define OB_STATUS_REJECTED 3

#define OB_FLAG_POST_ONLY 0x01u
#define OB_FLAG_REDUCE_ONLY 0x02u

#define OB_FREE_SENTINEL 0xFFFFFFFFu
#define OB_MAX_EXECUTIONS 256

typedef struct ObOrder {
    uint64_t id_lo;
    uint64_t id_hi;
    double price;
    uint32_t quantity;
    uint32_t orig_qty;
    uint64_t timestamp_ns;
    uint8_t side;
    uint8_t type;
    uint8_t tif;
    uint8_t flags;
    uint32_t priority;
    uint32_t hidden_qty;
    uint32_t next_idx;
    uint64_t pad;
} ObOrder;

typedef struct ObMatchingResult {
    uint64_t order_id_lo;
    uint64_t order_id_hi;
    uint32_t orig_qty;
    uint32_t filled_qty;
    uint32_t remain_qty;
    uint32_t status;
    double avg_price;
    uint32_t exec_count;
    uint32_t pad;
} ObMatchingResult;

typedef struct ObExecution {
    double fill_price;
    uint32_t fill_qty;
    uint32_t ctp_id_lo;
    uint32_t ctp_id_hi;
    uint32_t pad;
} ObExecution;

#ifdef __cplusplus
extern "C" {
#endif

void ob_init(void);
uint32_t ob_add_order(ObOrder *tmpl, ObMatchingResult *result, ObExecution *execs);
uint64_t ob_cancel_order(uint64_t id_lo, uint64_t id_hi);
uint32_t ob_match_bottom(ObOrder *incoming, ObMatchingResult *result, ObExecution *execs);
double ob_best_bid(void);
double ob_best_ask(void);
double ob_spread(void);
double ob_spread_bps(void);
double ob_mid_price(void);

#ifdef __cplusplus
}
#endif

static_assert(sizeof(ObOrder) == 64, "Order is one cache line");
static_assert(offsetof(ObOrder, price) == 16, "price offset");
static_assert(offsetof(ObOrder, quantity) == 24, "quantity offset");
static_assert(offsetof(ObOrder, timestamp_ns) == 32, "timestamp offset");
static_assert(offsetof(ObOrder, side) == 40, "side offset");
static_assert(offsetof(ObOrder, priority) == 44, "priority offset");
static_assert(offsetof(ObOrder, hidden_qty) == 48, "hidden_qty offset");
static_assert(offsetof(ObOrder, next_idx) == 52, "next_idx offset");
static_assert(sizeof(ObMatchingResult) == 48, "MatchingResult size");
static_assert(offsetof(ObMatchingResult, avg_price) == 32, "avg_price offset");
static_assert(offsetof(ObMatchingResult, exec_count) == 40, "exec_count offset");
static_assert(sizeof(ObExecution) == 24, "Execution size");
static_assert(offsetof(ObExecution, fill_qty) == 8, "fill_qty offset");

#endif
