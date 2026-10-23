; =============================================================================
; hft_orderbook.asm
; High-Frequency Trading Orderbook Matching Engine
; x86-64 NASM — Linux System V AMD64 ABI
;
; Refactored from HFTOrderbookProtocol.swift
; "Speed is the ultimate feature in trading."
; "Every microsecond matters. Every nanosecond counts."
;
; Assemble:  nasm -f elf64 hft_orderbook.asm -o hft_orderbook.o
; Link:      ld hft_orderbook.o -o hft_orderbook
; Run:       ./hft_orderbook
;
; ─── Calling Convention (System V AMD64) ─────────────────────────────────────
;   Integer args      rdi  rsi  rdx  rcx  r8   r9
;   Float args        xmm0 xmm1 xmm2 xmm3 xmm4 xmm5
;   Integer return    rax  (rdx for 128-bit)
;   Float return      xmm0
;   Callee-saved      rbx  r12  r13  r14  r15  rbp
;   Caller-saved      rax  rcx  rdx  rsi  rdi  r8–r11  xmm0–xmm7
;
; ─── Memory Layout ───────────────────────────────────────────────────────────
;
;  Order — 64 bytes (one cache line)
;    +0   id_lo        qword   UUID bits  0..63
;    +8   id_hi        qword   UUID bits 64..127
;   +16   price        double  limit price (0.0 = market order)
;   +24   quantity     dword   remaining quantity
;   +28   orig_qty     dword   original (immutable after add)
;   +32   timestamp_ns qword   CLOCK_MONOTONIC_RAW nanoseconds (time priority)
;   +40   side         byte    0=BUY  1=SELL
;   +41   type         byte    0=MARKET 1=LIMIT 2=STOP 3=STOP_LIMIT 4=ICEBERG
;   +42   tif          byte    0=GTC 1=IOC 2=FOK 3=DAY
;   +43   flags        byte    bit0=post_only  bit1=reduce_only
;   +44   priority     dword   higher → first at same price
;   +48   hidden_qty   dword   iceberg visible cap (0 = not iceberg)
;   +52   next_idx     dword   intrusive linked list within a price level;
;                              also used as free-list link when unallocated
;   +56   _pad         qword
;
;  PriceLevel — 32 bytes
;    +0   price        double  price key
;    +8   total_qty    qword   sum of all resting quantities at this level
;   +16   order_count  dword   number of resting orders
;   +20   head_idx     dword   pool index of first order (FREE_SENTINEL = none)
;   +24   visible_qty  qword   total_qty minus hidden iceberg amounts
;
;  MatchingResult — 48 bytes (caller-allocated, must be zero before call)
;    +0   order_id_lo  qword
;    +8   order_id_hi  qword
;   +16   orig_qty     dword
;   +20   filled_qty   dword
;   +24   remain_qty   dword
;   +28   status       dword   0=PENDING 1=FILLED 2=PARTIAL 3=REJECTED
;   +32   avg_price    double
;   +40   exec_count   dword
;   +44   _pad         dword
;
;  Execution — 24 bytes per fill (caller provides array)
;    +0   fill_price   double
;    +8   fill_qty     dword
;   +12   ctp_id_lo    dword   counterparty id low 32 bits
;   +16   ctp_id_hi    dword   counterparty id high 32 bits
;   +20   _pad         dword
;
; ─── Global Orderbook State (BSS, zero-initialised at startup) ───────────────
;   ob_bid_count  — active bid price levels (sorted descending: [0]=best bid)
;   ob_ask_count  — active ask price levels (sorted ascending:  [0]=best ask)
;   ob_seq        — monotonic sequence number, bumped on every state change
;   ob_order_cnt  — live orders in the pool
;   ob_free_head  — free-list head index  (FREE_SENTINEL = pool exhausted)
;   ob_bid_levels — MAX_PRICE_LEVELS × PriceLevel
;   ob_ask_levels — MAX_PRICE_LEVELS × PriceLevel
;   ob_order_pool — MAX_ORDERS × Order
; =============================================================================

BITS 64

; ─── Order side ──────────────────────────────────────────────────────────────
SIDE_BUY            equ 0
SIDE_SELL           equ 1

; ─── Order type ──────────────────────────────────────────────────────────────
TYPE_MARKET         equ 0
TYPE_LIMIT          equ 1
TYPE_STOP           equ 2
TYPE_STOP_LIMIT     equ 3
TYPE_ICEBERG        equ 4

; ─── Time-in-force ───────────────────────────────────────────────────────────
TIF_GTC             equ 0       ; Good-till-cancelled
TIF_IOC             equ 1       ; Immediate-or-cancel
TIF_FOK             equ 2       ; Fill-or-kill
TIF_DAY             equ 3       ; Day order

; ─── Execution status ────────────────────────────────────────────────────────
STATUS_PENDING      equ 0
STATUS_FILLED       equ 1
STATUS_PARTIAL      equ 2
STATUS_REJECTED     equ 3

; ─── Order flags (byte at +43) ───────────────────────────────────────────────
FLAG_POST_ONLY      equ 0x01
FLAG_REDUCE_ONLY    equ 0x02

; ─── Order struct offsets ────────────────────────────────────────────────────
O_ID_LO             equ 0
O_ID_HI             equ 8
O_PRICE             equ 16
O_QTY               equ 24
O_ORIG_QTY          equ 28
O_TS_NS             equ 32
O_SIDE              equ 40
O_TYPE              equ 41
O_TIF               equ 42
O_FLAGS             equ 43
O_PRIORITY          equ 44
O_HIDDEN_QTY        equ 48
O_NEXT              equ 52          ; intrusive list / free-list link
; O_PAD              equ 56
O_SIZE              equ 64          ; MUST be a power of 2 (shift = 6)
O_SHIFT             equ 6           ; log2(O_SIZE)

; ─── PriceLevel struct offsets ───────────────────────────────────────────────
L_PRICE             equ 0
L_TOTAL_QTY         equ 8
L_ORDER_COUNT       equ 16
L_HEAD              equ 20          ; pool index of first order
L_VISIBLE_QTY       equ 24
L_SIZE              equ 32          ; MUST be a power of 2 (shift = 5)
L_SHIFT             equ 5           ; log2(L_SIZE)

; ─── MatchingResult offsets ──────────────────────────────────────────────────
R_ID_LO             equ 0
R_ID_HI             equ 8
R_ORIG_QTY          equ 16
R_FILLED_QTY        equ 20
R_REMAIN_QTY        equ 24
R_STATUS            equ 28
R_AVG_PRICE         equ 32
R_EXEC_COUNT        equ 40
R_SIZE              equ 48

; ─── Execution record offsets ────────────────────────────────────────────────
E_FILL_PRICE        equ 0
E_FILL_QTY          equ 8
E_CTP_ID_LO         equ 12
E_CTP_ID_HI         equ 16
E_SIZE              equ 24

; ─── Capacity ────────────────────────────────────────────────────────────────
MAX_PRICE_LEVELS    equ 4096        ; per side — 128 KB per side for levels
MAX_ORDERS          equ 65536       ; total pool — 4 MB
MAX_EXECUTIONS      equ 256         ; per match call
FREE_SENTINEL       equ 0xFFFFFFFF  ; end-of-list sentinel for dword indices

; ─── Syscall numbers (Linux x86-64) ──────────────────────────────────────────
SYS_write           equ 1
SYS_exit            equ 60
SYS_clock_gettime   equ 228

CLOCK_MONOTONIC_RAW equ 4
STDOUT_FD           equ 1


; =============================================================================
; .data — initialised constants
; =============================================================================
section .data align=16

align 8
k_half:             dq  0.5
k_ten_thousand:     dq  10000.0
k_f64_nan:          dq  0x7FF8000000000000   ; canonical quiet NaN
k_hundred:          dq  100.0
k_999:              dq  999.0               ; pool exhaustion test price

; =============================================================================
; .bss — zero-initialised global state (one orderbook, statically allocated)
; =============================================================================
section .bss align=64

; Scalar state ─────────────────────────────────────────────────────────────────
ob_bid_count:       resq 1
ob_ask_count:       resq 1
ob_seq:             resq 1
ob_order_cnt:       resq 1
ob_free_head:       resd 1
                    resd 1          ; alignment pad

; Level arrays ─────────────────────────────────────────────────────────────────
alignb 64
ob_bid_levels:      resb  MAX_PRICE_LEVELS * L_SIZE
ob_ask_levels:      resb  MAX_PRICE_LEVELS * L_SIZE

; Order pool ───────────────────────────────────────────────────────────────────
alignb 64
ob_order_pool:      resb  MAX_ORDERS * O_SIZE

; Scratch for clock_gettime ────────────────────────────────────────────────────
alignb 8
_ts_sec:            resq 1
_ts_nsec:           resq 1

; Print scratch ────────────────────────────────────────────────────────────────
align 1
_print_buf:         resb 32

; =============================================================================
; .rodata — strings
; =============================================================================
section .rodata

s_banner:       db  "=== HFT Orderbook Matching Engine (x86-64 NASM) ===", 10, 0
s_bid:          db  "Best bid : ", 0
s_ask:          db  "Best ask : ", 0
s_spread:       db  "Spread   : ", 0
s_mid:          db  "Mid      : ", 0
s_none:         db  "(none)", 10, 0
s_match:        db  "Match -> ", 0
s_filled:       db  "FILLED",          10, 0
s_partial:      db  "PARTIAL_FILL",    10, 0
s_pending:      db  "PENDING",         10, 0
s_rejected:     db  "REJECTED",        10, 0
s_filled_q:     db  "  filled_qty=", 0
s_avg_px:       db  "  avg_price=",  0
s_newline:      db  10, 0
s_done:         db  "=== example complete ===", 10, 0
; ── test strings ────────────────────────────────────────────────────────────
s_t_cancel:     db  10, "[TEST 1] ob_cancel_order — UUID scan-and-unlink", 10, 0
s_t_fok:        db  10, "[TEST 2] FOK rejection — insufficient liquidity",  10, 0
s_t_pool:       db  10, "[TEST 3] Pool exhaustion — 65536 allocs",          10, 0
s_pass:         db  "  => PASS", 10, 0
s_fail:         db  "  => FAIL", 10, 0
s_ask_count:    db  "  ask_count=", 0
s_bid_count:    db  "  bid_count=", 0
s_cancel_ret:   db  "  cancel()=", 0
s_placed:       db  "  orders_placed=", 0
s_alloc65537:   db  "  alloc#65537 returned ", 0
s_free_head:    db  "  ob_free_head=", 0
s_null_ptr:     db  "NULL — pool empty (correct)", 10, 0
s_nonzero:      db  "non-zero (WRONG)", 10, 0
s_remain_qty:   db  "  remain_qty=", 0


; =============================================================================
; .text
; =============================================================================
section .text align=16

global ob_init
global ob_add_order
global ob_cancel_order
global ob_match_bottom
global ob_best_bid
global ob_best_ask
global ob_spread
global ob_spread_bps
global ob_mid_price
global _start


; =============================================================================
; ob_init — initialise the global orderbook state
; Builds the free list: pool[i].next_idx = i+1  (pool[MAX-1].next = sentinel)
; args : none   ret : none
; =============================================================================
ob_init:
        ; Clear scalar state (BSS is already zero at program start, but
        ; allow re-initialisation at runtime without restarting)
        xor     eax, eax
        mov     [rel ob_bid_count], rax
        mov     [rel ob_ask_count], rax
        mov     [rel ob_seq],       rax
        mov     [rel ob_order_cnt], rax

        ; Build free list: slot i → next = i+1; last slot → FREE_SENTINEL
        lea     rdi, [rel ob_order_pool]
        xor     ecx, ecx                ; current index

.free_init_loop:
        ; write next_idx into slot at [rdi + O_NEXT]
        mov     eax, ecx
        inc     eax                     ; eax = i + 1
        cmp     eax, MAX_ORDERS
        jne     .not_last_slot
        mov     eax, FREE_SENTINEL
.not_last_slot:
        mov     [rdi + O_NEXT], eax
        add     rdi, O_SIZE             ; advance pointer
        inc     ecx
        cmp     ecx, MAX_ORDERS
        jne     .free_init_loop

        ; Head of free list = slot 0
        xor     eax, eax
        mov     [rel ob_free_head], eax
        ret


; =============================================================================
; _timestamp_ns — CLOCK_MONOTONIC_RAW nanoseconds since boot
; args : none   ret : rax = ns
; clobbers : rax rdi rsi r11 rcx (syscall ABI)
; =============================================================================
_timestamp_ns:
        mov     eax, SYS_clock_gettime
        mov     edi, CLOCK_MONOTONIC_RAW
        lea     rsi, [rel _ts_sec]
        syscall
        ; result: [_ts_sec] = tv_sec, [_ts_nsec] = tv_nsec
        mov     rax, [rel _ts_sec]
        mov     rcx, 1000000000
        mul     rcx                     ; rax = sec * 1e9  (rdx = overflow, ignored)
        add     rax, [rel _ts_nsec]
        ret


; =============================================================================
; _pool_ptr — convert pool index → pointer
; args : edi = index (dword)   ret : rax = pointer  (0 if FREE_SENTINEL)
; clobbers : rax
; =============================================================================
_pool_ptr:
        cmp     edi, FREE_SENTINEL
        je      .invalid
        mov     eax, edi                ; zero-extend index to 64-bit (mov r32 auto-zeros r64)
        shl     rax, O_SHIFT            ; × O_SIZE (64)
        lea     rdx, [rel ob_order_pool]
        add     rax, rdx
        ret
.invalid:
        xor     eax, eax
        ret


; =============================================================================
; _pool_idx — convert pool pointer → index
; args : rdi = pointer   ret : eax = index
; clobbers : rax rdx
; =============================================================================
_pool_idx:
        lea     rdx, [rel ob_order_pool]
        sub     rdi, rdx                ; byte offset
        shr     rdi, O_SHIFT            ; ÷ O_SIZE
        mov     eax, edi
        ret


; =============================================================================
; _alloc_order — pop one Order from the free list
; args : none   ret : rax = pointer to zeroed slot  (0 if pool exhausted)
; clobbers : rax rcx rdx
; =============================================================================
_alloc_order:
        mov     eax, [rel ob_free_head]
        cmp     eax, FREE_SENTINEL
        je      .full

        ; Compute pointer  (rax = old head index)
        mov     ecx, eax                ; zero-extends to rcx
        shl     rcx, O_SHIFT
        lea     rdx, [rel ob_order_pool]
        add     rdx, rcx                ; rdx = slot pointer

        ; Advance free_head before zeroing (ORDER_NEXT holds next link)
        mov     ecx, [rdx + O_NEXT]
        mov     [rel ob_free_head], ecx

        ; Zero the 64-byte slot
        pxor    xmm0, xmm0
        movdqu  [rdx],    xmm0
        movdqu  [rdx+16], xmm0
        movdqu  [rdx+32], xmm0
        movdqu  [rdx+48], xmm0

        ; Mark as live (end of intrusive list)
        mov     dword [rdx + O_NEXT], FREE_SENTINEL

        inc     qword [rel ob_order_cnt]
        mov     rax, rdx
        ret
.full:
        xor     eax, eax
        ret


; =============================================================================
; _free_order — push one Order slot back onto the free list
; args : rdi = pointer to slot   ret : none
; clobbers : rax rcx
; =============================================================================
_free_order:
        ; Compute byte offset from pool base
        lea     rax, [rel ob_order_pool]
        sub     rdi, rax                ; byte offset (rdi is now scratch)
        shr     rdi, O_SHIFT            ; pool index

        ; slot.next_idx = old free_head
        mov     eax, [rel ob_free_head]
        ; write into pool: base + idx*O_SIZE + O_NEXT
        lea     rcx, [rel ob_order_pool]
        lea     rax, [rcx + rdi*8]      ; rdi already = index; *8 ≠ *64
        ; Fix: multiply index correctly (can't use scale=64 in SIB)
        mov     rax, rdi
        shl     rax, O_SHIFT            ; byte offset
        add     rax, rcx                ; rax = slot pointer
        mov     ecx, [rel ob_free_head]
        mov     [rax + O_NEXT], ecx     ; chain into free list

        ; new free_head = this slot's index
        mov     ecx, [rel ob_free_head] ; save old head (now in ecx, overwritten above)
        ; actually we already wrote the old head into the slot; retrieve index:
        lea     rcx, [rel ob_order_pool]
        sub     rax, rcx
        shr     rax, O_SHIFT            ; back to index
        mov     [rel ob_free_head], eax

        dec     qword [rel ob_order_cnt]
        ret


; =============================================================================
; _level_ptr_bid / _level_ptr_ask — index → level pointer
; args : rdi = index   ret : rax = pointer
; =============================================================================
_level_ptr_bid:
        mov     rax, rdi
        shl     rax, L_SHIFT
        lea     rdx, [rel ob_bid_levels]
        add     rax, rdx
        ret

_level_ptr_ask:
        mov     rax, rdi
        shl     rax, L_SHIFT
        lea     rdx, [rel ob_ask_levels]
        add     rax, rdx
        ret


; =============================================================================
; _bid_find — binary search for price in bid levels (sorted DESCENDING)
; args : xmm0 = target price
; ret  : rax = index  |  rdx = 1 found / 0 insertion point
; clobbers : rax rcx rdx r8 r9 r10 xmm1
; =============================================================================
_bid_find:
        mov     rcx, [rel ob_bid_count]
        test    rcx, rcx
        jz      .empty

        xor     r8, r8                  ; lo = 0
        lea     r9, [rcx - 1]           ; hi = count - 1
        lea     r10, [rel ob_bid_levels]

.loop:
        cmp     r8, r9
        jg      .miss
        mov     rax, r8
        add     rax, r9
        shr     rax, 1                  ; mid = (lo+hi)/2
        mov     rcx, rax
        shl     rcx, L_SHIFT            ; byte offset = mid * L_SIZE
        movsd   xmm1, [r10 + rcx + L_PRICE]
        ucomisd xmm1, xmm0
        je      .hit
        ja      .go_right               ; levels[mid].price > target → higher idx
        lea     r9, [rax - 1]           ; hi = mid-1  (target is bigger, lower idx in desc order)
        jmp     .loop
.go_right:
        lea     r8, [rax + 1]           ; lo = mid+1
        jmp     .loop
.hit:
        mov     edx, 1
        ret
.miss:
        mov     rax, r8                 ; insertion point = lo
        xor     edx, edx
        ret
.empty:
        xor     rax, rax
        xor     edx, edx
        ret


; =============================================================================
; _ask_find — binary search for price in ask levels (sorted ASCENDING)
; args : xmm0 = target price
; ret  : rax = index  |  rdx = 1 found / 0 insertion point
; =============================================================================
_ask_find:
        mov     rcx, [rel ob_ask_count]
        test    rcx, rcx
        jz      .empty

        xor     r8, r8
        lea     r9, [rcx - 1]
        lea     r10, [rel ob_ask_levels]

.loop:
        cmp     r8, r9
        jg      .miss
        mov     rax, r8
        add     rax, r9
        shr     rax, 1
        mov     rcx, rax
        shl     rcx, L_SHIFT
        movsd   xmm1, [r10 + rcx + L_PRICE]
        ucomisd xmm1, xmm0
        je      .hit
        jb      .go_right               ; levels[mid].price < target → higher idx
        lea     r9, [rax - 1]
        jmp     .loop
.go_right:
        lea     r8, [rax + 1]
        jmp     .loop
.hit:
        mov     edx, 1
        ret
.miss:
        mov     rax, r8
        xor     edx, edx
        ret
.empty:
        xor     rax, rax
        xor     edx, edx
        ret


; =============================================================================
; _bid_open_slot / _ask_open_slot
; Insert a new zeroed PriceLevel slot at position rdi, shifting higher entries.
; Bid array sorted descending; ask array sorted ascending.
;
; args : rdi = insertion index
; ret  : rax = pointer to newly created slot (0 if array full)
; clobbers : rax rcx rdx rsi rdi r8 r9
; =============================================================================
_bid_open_slot:
        push    rbx
        mov     rbx, rdi                ; save insertion index

        mov     rcx, [rel ob_bid_count]
        cmp     rcx, MAX_PRICE_LEVELS
        jge     .full

        ; Shift entries [rbx .. rcx-1] one slot to the right.
        ; Copy backwards to handle the overlap (dst > src).
        ;   n_levels_to_shift = count - rbx
        ;   bytes_to_shift    = n_levels_to_shift * L_SIZE
        mov     rax, rcx
        sub     rax, rbx                ; n = count - insertion_index
        test    rax, rax
        jle     .no_shift

        ; source range: &bid_levels[rbx]  ..  &bid_levels[rcx-1]
        ; dest range:   &bid_levels[rbx+1] .. &bid_levels[rcx]
        ; (all dst > src, so copy right-to-left)
        ;
        ;   src_end = &bid_levels[rcx] - 1   (= &bid_levels[count] - 1)
        ;   dst_end = &bid_levels[rcx+1] - 1 (= src_end + L_SIZE)
        lea     r8, [rel ob_bid_levels]
        mov     r9, rcx
        shl     r9, L_SHIFT             ; r9 = count * L_SIZE
        lea     rsi, [r8 + r9 - 1]     ; rsi = src_end
        lea     rdi, [rsi + L_SIZE]     ; rdi = dst_end
        imul    rax, L_SIZE             ; rax = bytes to move
        mov     rcx, rax
        std                             ; decrement rsi/rdi each step
        rep     movsb
        cld

.no_shift:
        ; Zero the new slot at index rbx
        lea     r8, [rel ob_bid_levels]
        mov     rax, rbx
        shl     rax, L_SHIFT
        add     rax, r8                 ; rax = &bid_levels[rbx]
        pxor    xmm0, xmm0
        movdqu  [rax],    xmm0
        movdqu  [rax+16], xmm0
        ; Set head to sentinel (no orders yet)
        mov     dword [rax + L_HEAD], FREE_SENTINEL

        inc     qword [rel ob_bid_count]
        pop     rbx
        ret
.full:
        xor     eax, eax
        pop     rbx
        ret


_ask_open_slot:
        push    rbx
        mov     rbx, rdi

        mov     rcx, [rel ob_ask_count]
        cmp     rcx, MAX_PRICE_LEVELS
        jge     .full

        mov     rax, rcx
        sub     rax, rbx
        test    rax, rax
        jle     .no_shift

        lea     r8, [rel ob_ask_levels]
        mov     r9, rcx
        shl     r9, L_SHIFT
        lea     rsi, [r8 + r9 - 1]
        lea     rdi, [rsi + L_SIZE]
        imul    rax, L_SIZE
        mov     rcx, rax
        std
        rep     movsb
        cld

.no_shift:
        lea     r8, [rel ob_ask_levels]
        mov     rax, rbx
        shl     rax, L_SHIFT
        add     rax, r8
        pxor    xmm0, xmm0
        movdqu  [rax],    xmm0
        movdqu  [rax+16], xmm0
        mov     dword [rax + L_HEAD], FREE_SENTINEL

        inc     qword [rel ob_ask_count]
        pop     rbx
        ret
.full:
        xor     eax, eax
        pop     rbx
        ret


; =============================================================================
; _bid_collapse / _ask_collapse — remove (now-empty) level at index rdi
; Shifts all subsequent levels left by one slot.
; args : rdi = index of empty level   ret : none
; clobbers : rax rcx rdx rsi rdi
; =============================================================================
_bid_collapse:
        push    r8
        mov     rcx, [rel ob_bid_count]
        dec     rcx                     ; rcx = count - 1
        mov     rax, rcx
        sub     rax, rdi                ; n = (count-1) - idx = levels after slot
        test    rax, rax
        jle     .decrement

        ; Copy levels [idx+1 .. count-1] to [idx .. count-2]  (left shift)
        lea     r8, [rel ob_bid_levels]
        mov     rdx, rdi
        inc     rdx
        shl     rdx, L_SHIFT
        add     rdx, r8                 ; rdx = src = &bid_levels[idx+1]
        mov     rdi, rdi
        shl     rdi, L_SHIFT
        add     rdi, r8                 ; rdi = dst = &bid_levels[idx]
        imul    rax, L_SIZE             ; bytes to move
        mov     rcx, rax
        cld
        rep     movsb

.decrement:
        dec     qword [rel ob_bid_count]
        pop     r8
        ret


_ask_collapse:
        push    r8
        mov     rcx, [rel ob_ask_count]
        dec     rcx
        mov     rax, rcx
        sub     rax, rdi
        test    rax, rax
        jle     .decrement

        lea     r8, [rel ob_ask_levels]
        mov     rdx, rdi
        inc     rdx
        shl     rdx, L_SHIFT
        add     rdx, r8
        mov     rdi, rdi
        shl     rdi, L_SHIFT
        add     rdi, r8
        imul    rax, L_SIZE
        mov     rcx, rax
        cld
        rep     movsb

.decrement:
        dec     qword [rel ob_ask_count]
        pop     r8
        ret


; =============================================================================
; _level_add_order — prepend an order to a price level's intrusive list
; args : rax = level pointer
;        rbx = order pool index
;        ecx = order quantity (for totals)
; ret  : none
; clobbers : rdx
; =============================================================================
_level_add_order:
        ; new_order.next = old head
        mov     edx, [rax + L_HEAD]
        ; get slot pointer
        push    rdi
        mov     edi, ebx
        push    rax
        push    rcx
        call    _pool_ptr               ; rax = order pointer
        pop     rcx
        mov     rdx, rax
        pop     rax                     ; restore level pointer
        pop     rdi
        ; write next into order
        mov     r8d, [rax + L_HEAD]
        mov     [rdx + O_NEXT], r8d
        ; level.head = new order index
        mov     [rax + L_HEAD], ebx
        ; update totals
        add     qword [rax + L_TOTAL_QTY],   rcx
        add     qword [rax + L_VISIBLE_QTY], rcx
        inc     dword [rax + L_ORDER_COUNT]
        ret


; =============================================================================
; ob_best_bid — return best bid price
; args : none   ret : xmm0 = price (NaN if empty)
; =============================================================================
ob_best_bid:
        mov     rax, [rel ob_bid_count]
        test    rax, rax
        jz      .empty
        movsd   xmm0, [rel ob_bid_levels + L_PRICE]   ; level[0]
        ret
.empty:
        movsd   xmm0, [rel k_f64_nan]
        ret


; =============================================================================
; ob_best_ask — return best ask price
; args : none   ret : xmm0 = price (NaN if empty)
; =============================================================================
ob_best_ask:
        mov     rax, [rel ob_ask_count]
        test    rax, rax
        jz      .empty
        movsd   xmm0, [rel ob_ask_levels + L_PRICE]   ; level[0]
        ret
.empty:
        movsd   xmm0, [rel k_f64_nan]
        ret


; =============================================================================
; ob_spread — (best ask) - (best bid)   ; 0.0 if either side empty
; args : none   ret : xmm0
; =============================================================================
ob_spread:
        call    ob_best_bid
        movsd   xmm2, xmm0
        call    ob_best_ask
        ucomisd xmm0, xmm2              ; NaN comparison sets PF
        jp      .no_spread
        subsd   xmm0, xmm2
        ret
.no_spread:
        pxor    xmm0, xmm0
        ret


; =============================================================================
; ob_spread_bps — spread in basis points:  (ask-bid)/bid × 10000
; args : none   ret : xmm0   (0.0 if either side empty)
; =============================================================================
ob_spread_bps:
        call    ob_best_bid
        ucomisd xmm0, xmm0              ; NaN test
        jp      .no_data
        movsd   xmm2, xmm0             ; xmm2 = bid
        call    ob_best_ask
        ucomisd xmm0, xmm0
        jp      .no_data
        subsd   xmm0, xmm2             ; spread = ask - bid
        divsd   xmm0, xmm2             ; spread / bid
        mulsd   xmm0, [rel k_ten_thousand]
        ret
.no_data:
        pxor    xmm0, xmm0
        ret


; =============================================================================
; ob_mid_price — (best_bid + best_ask) / 2
; args : none   ret : xmm0   (NaN if either side empty)
; =============================================================================
ob_mid_price:
        call    ob_best_bid
        ucomisd xmm0, xmm0
        jp      .no_mid
        movsd   xmm2, xmm0
        call    ob_best_ask
        ucomisd xmm0, xmm0
        jp      .no_mid
        addsd   xmm0, xmm2
        mulsd   xmm0, [rel k_half]
        ret
.no_mid:
        movsd   xmm0, [rel k_f64_nan]
        ret


; =============================================================================
; ob_match_bottom — price-time priority matching engine
;
; Attempts to fill an incoming order against the opposite side of the book,
; consuming price levels from best to worst.  Matching behaviour by order type:
;
;   MARKET / IOC:  fill as much as possible at any available price
;   LIMIT  buy:    fill while limit_price >= current ask level price
;   LIMIT  sell:   fill while limit_price <= current bid level price
;
; "Matching is where the magic happens."
; "Every match is a trade. Every trade is profit."
;
; args : rdi = pointer to incoming Order (O_QTY = quantity to fill)
;        rsi = pointer to MatchingResult (caller-zeroes before call)
;        rdx = pointer to Execution array (caller provides MAX_EXECUTIONS slots)
; ret  : rax = ExecutionStatus
;
; Register allocation inside this function:
;   r12 = incoming order pointer
;   r13 = MatchingResult pointer
;   r14 = Execution array pointer
;   r15 = remaining quantity (64-bit)
;   rbx = execution count
;   xmm13 (via stack) = accumulated fill value (price×qty)
;   rbp = scratch level pointer during matching loops
; =============================================================================
ob_match_bottom:
        push    r12
        push    r13
        push    r14
        push    r15
        push    rbx
        push    rbp
        sub     rsp, 16                 ; 8-byte align + xmm scratch

        mov     r12, rdi
        mov     r13, rsi
        mov     r14, rdx

        ; Copy order id into result
        mov     rax, [r12 + O_ID_LO]
        mov     [r13 + R_ID_LO], rax
        mov     rax, [r12 + O_ID_HI]
        mov     [r13 + R_ID_HI], rax

        ; Record quantities
        mov     r15d, dword [r12 + O_QTY]   ; zero-extends to r15
        mov     [r13 + R_ORIG_QTY],   r15d
        mov     [r13 + R_REMAIN_QTY], r15d
        mov     dword [r13 + R_STATUS], STATUS_PENDING

        ; xmm save slot on stack at [rsp]: accumulated fill value
        pxor    xmm0, xmm0
        movsd   [rsp], xmm0

        xor     ebx, ebx               ; exec_count = 0

        ; Dispatch on side × type
        movzx   eax, byte [r12 + O_SIDE]
        movzx   ecx, byte [r12 + O_TYPE]

        cmp     al, SIDE_BUY
        je      .buy_entry

        ; ── SELL: match against bid levels (sorted descending, [0]=best) ──────
.sell_entry:
        ; For LIMIT sell: skip if limit_price > best_bid
        cmp     cl, TYPE_LIMIT
        jne     .sell_loop
        mov     rax, [rel ob_bid_count]
        test    rax, rax
        jz      .finalize
        movsd   xmm1, [rel ob_bid_levels + L_PRICE]   ; best bid
        movsd   xmm2, [r12 + O_PRICE]                 ; limit price
        ucomisd xmm2, xmm1
        ja      .finalize              ; limit_price > best_bid → no cross

.sell_loop:
        test    r15, r15
        jz      .finalize
        mov     rax, [rel ob_bid_count]
        test    rax, rax
        jz      .finalize

        lea     rbp, [rel ob_bid_levels]   ; rbp = &bid_levels[0] = best level
        movsd   xmm1, [rbp + L_PRICE]     ; current best bid price

        ; Limit price check: stop if limit_price > level_price
        cmp     cl, TYPE_LIMIT
        jne     .sell_fill_level
        movsd   xmm2, [r12 + O_PRICE]
        ucomisd xmm2, xmm1
        ja      .finalize

.sell_fill_level:
        ; Walk the intrusive order list at this bid level (FIFO)
        mov     r8d, [rbp + L_HEAD]

.sell_order_loop:
        cmp     r8d, FREE_SENTINEL
        je      .sell_level_exhausted
        test    r15, r15
        jz      .finalize

        ; Get resting order pointer
        mov     edi, r8d
        call    _pool_ptr               ; rax = resting order ptr
        mov     r9, rax                 ; r9 = resting order ptr

        ; fill_qty = min(r15, resting.qty)
        mov     r10d, dword [r9 + O_QTY]    ; zero-extends to r10
        cmp     r15, r10
        jle     .sell_fill_partial
        mov     r11, r10                ; fill = resting qty (fully consume resting)
        jmp     .sell_execute
.sell_fill_partial:
        mov     r11, r15                ; fill = all remaining incoming

.sell_execute:
        ; Record execution  (if space remains in caller array)
        cmp     ebx, MAX_EXECUTIONS
        jge     .sell_skip_exec
        mov     rax, rbx
        imul    rax, E_SIZE
        add     rax, r14                ; rax = &exec[exec_count]
        movsd   [rax + E_FILL_PRICE], xmm1
        mov     [rax + E_FILL_QTY],   r11d
        mov     edx, [r9 + O_ID_LO]    ; counterparty id (lo 32-bits)
        mov     [rax + E_CTP_ID_LO],  edx
        mov     edx, [r9 + O_ID_HI]
        mov     [rax + E_CTP_ID_HI],  edx
        inc     ebx
.sell_skip_exec:

        ; Accumulate fill value: total_value += price × fill_qty
        movsd   xmm2, xmm1
        cvtsi2sd xmm3, r11
        mulsd   xmm2, xmm3
        movsd   xmm4, [rsp]
        addsd   xmm4, xmm2
        movsd   [rsp], xmm4

        sub     r15, r11                ; remaining incoming -= fill

        ; Update resting order
        sub     dword [r9 + O_QTY], r11d
        jnz     .sell_partial_resting   ; resting order partially filled → stays

        ; Resting order fully consumed: remove from list and pool
        mov     r8d, [r9 + O_NEXT]     ; advance list head to next
        mov     [rbp + L_HEAD], r8d
        sub     qword [rbp + L_TOTAL_QTY],   r11
        sub     qword [rbp + L_VISIBLE_QTY], r11
        dec     dword [rbp + L_ORDER_COUNT]
        ; Free resting order
        mov     rdi, r9
        call    _free_order
        ; rbp still points to bid_levels[0] (not invalidated)
        ; Check if level is now empty → collapse it
        cmp     dword [rbp + L_ORDER_COUNT], 0
        jne     .sell_order_loop
        xor     edi, edi                ; index = 0 (best bid level)
        call    _bid_collapse
        jmp     .sell_loop              ; restart loop with updated best bid

.sell_partial_resting:
        ; Resting order partially filled, incoming order fully consumed
        sub     qword [rbp + L_TOTAL_QTY],   r11
        sub     qword [rbp + L_VISIBLE_QTY], r11
        jmp     .finalize

.sell_level_exhausted:
        ; Shouldn't happen if L_ORDER_COUNT is consistent, but guard it:
        xor     edi, edi
        call    _bid_collapse
        jmp     .sell_loop

        ; ── BUY: match against ask levels (sorted ascending, [0]=best) ────────
.buy_entry:
        cmp     cl, TYPE_LIMIT
        jne     .buy_loop
        mov     rax, [rel ob_ask_count]
        test    rax, rax
        jz      .finalize
        movsd   xmm1, [rel ob_ask_levels + L_PRICE]
        movsd   xmm2, [r12 + O_PRICE]
        ucomisd xmm2, xmm1
        jb      .finalize              ; limit_price < best_ask → no cross

.buy_loop:
        test    r15, r15
        jz      .finalize
        mov     rax, [rel ob_ask_count]
        test    rax, rax
        jz      .finalize

        lea     rbp, [rel ob_ask_levels]
        movsd   xmm1, [rbp + L_PRICE]

        cmp     cl, TYPE_LIMIT
        jne     .buy_fill_level
        movsd   xmm2, [r12 + O_PRICE]
        ucomisd xmm2, xmm1
        jb      .finalize

.buy_fill_level:
        mov     r8d, [rbp + L_HEAD]

.buy_order_loop:
        cmp     r8d, FREE_SENTINEL
        je      .buy_level_exhausted
        test    r15, r15
        jz      .finalize

        mov     edi, r8d
        call    _pool_ptr
        mov     r9, rax

        mov     r10d, dword [r9 + O_QTY]    ; zero-extends to r10
        cmp     r15, r10
        jle     .buy_fill_partial
        mov     r11, r10
        jmp     .buy_execute
.buy_fill_partial:
        mov     r11, r15

.buy_execute:
        cmp     ebx, MAX_EXECUTIONS
        jge     .buy_skip_exec
        mov     rax, rbx
        imul    rax, E_SIZE
        add     rax, r14
        movsd   [rax + E_FILL_PRICE], xmm1
        mov     [rax + E_FILL_QTY],   r11d
        mov     edx, [r9 + O_ID_LO]
        mov     [rax + E_CTP_ID_LO],  edx
        mov     edx, [r9 + O_ID_HI]
        mov     [rax + E_CTP_ID_HI],  edx
        inc     ebx
.buy_skip_exec:

        movsd   xmm2, xmm1
        cvtsi2sd xmm3, r11
        mulsd   xmm2, xmm3
        movsd   xmm4, [rsp]
        addsd   xmm4, xmm2
        movsd   [rsp], xmm4

        sub     r15, r11
        sub     dword [r9 + O_QTY], r11d
        jnz     .buy_partial_resting

        mov     r8d, [r9 + O_NEXT]
        mov     [rbp + L_HEAD], r8d
        sub     qword [rbp + L_TOTAL_QTY],   r11
        sub     qword [rbp + L_VISIBLE_QTY], r11
        dec     dword [rbp + L_ORDER_COUNT]
        mov     rdi, r9
        call    _free_order
        cmp     dword [rbp + L_ORDER_COUNT], 0
        jne     .buy_order_loop
        xor     edi, edi
        call    _ask_collapse
        jmp     .buy_loop

.buy_partial_resting:
        sub     qword [rbp + L_TOTAL_QTY],   r11
        sub     qword [rbp + L_VISIBLE_QTY], r11
        jmp     .finalize

.buy_level_exhausted:
        xor     edi, edi
        call    _ask_collapse
        jmp     .buy_loop

        ; ── Finalise MatchingResult ───────────────────────────────────────────
.finalize:
        ; filled_qty = orig_qty - remaining
        mov     eax, [r13 + R_ORIG_QTY]
        sub     eax, r15d               ; eax = filled_qty
        mov     [r13 + R_FILLED_QTY],  eax
        mov     [r13 + R_REMAIN_QTY],  r15d
        mov     [r13 + R_EXEC_COUNT],  ebx

        ; avg_price = total_value / filled_qty  (0.0 if no fills)
        test    eax, eax
        jz      .zero_avg
        cvtsi2sd xmm0, rax              ; xmm0 = (double) filled_qty
        movsd   xmm1, [rsp]            ; accumulated fill value
        divsd   xmm1, xmm0
        movsd   [r13 + R_AVG_PRICE], xmm1
        jmp     .set_status
.zero_avg:
        pxor    xmm0, xmm0
        movsd   [r13 + R_AVG_PRICE], xmm0

.set_status:
        mov     ecx, [r13 + R_ORIG_QTY]
        mov     edx, [r13 + R_FILLED_QTY]
        xor     eax, eax                ; PENDING
        test    edx, edx
        jz      .done_status
        cmp     edx, ecx
        je      .is_filled
        mov     eax, STATUS_PARTIAL
        jmp     .done_status
.is_filled:
        mov     eax, STATUS_FILLED
.done_status:
        mov     [r13 + R_STATUS], eax

        inc     qword [rel ob_seq]

        add     rsp, 16
        pop     rbp
        pop     rbx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret


; =============================================================================
; _fok_available — pre-scan opposite side to see if a FOK order can fully fill
;
; Counts crossable resting quantity WITHOUT touching/modifying any state.
; A FOK order must be fully fillable before we execute even one trade —
; otherwise we'd have to undo partial fills, which the simple engine here
; doesn't support.
;
; args : rdi = pointer to the (already pool-allocated) incoming order
; ret  : eax = 1  enough liquidity to fully fill
;        eax = 0  insufficient — caller should reject and return FREE_SENTINEL
;
; clobbers : rax rcx rdx r8 r9 r10 xmm0 xmm1
; =============================================================================
_fok_available:
        movzx   ecx, byte [rdi + O_TYPE]     ; order type (MARKET vs LIMIT)
        mov     r8d,  dword [rdi + O_QTY]    ; needed quantity
        movsd   xmm0, [rdi + O_PRICE]        ; limit price (0.0 for MARKET)

        movzx   eax, byte [rdi + O_SIDE]
        test    eax, eax
        jz      .buy_side                    ; SIDE_BUY → scan asks

        ; ── SELL: count resting bid quantity at crossable prices ──────────────
        ; Bids sorted descending, so walk from index 0 while bid.price >= limit
        mov     r9,  [rel ob_bid_count]
        test    r9, r9
        jz      .insufficient
        xor     r10, r10                     ; level index = 0
        xor     rdx, rdx                     ; accumulated available
        lea     rax, [rel ob_bid_levels]
.sell_scan:
        cmp     r10, r9
        jge     .check
        mov     rcx, r10
        shl     rcx, L_SHIFT
        add     rcx, rax                     ; rcx = &bid_levels[r10]
        ; For LIMIT sell: stop once bid.price < our limit price
        movzx   r8d, byte [rdi + O_TYPE]
        cmp     r8d, TYPE_MARKET
        je      .sell_accum
        movsd   xmm1, [rcx + L_PRICE]
        ucomisd xmm1, xmm0                  ; bid.price vs limit_sell
        jb      .check                      ; bid below our floor → no more crosses
.sell_accum:
        mov     r8d, dword [rdi + O_QTY]    ; reload needed (r8d may have changed)
        add     rdx, qword [rcx + L_TOTAL_QTY]
        cmp     rdx, r8
        jge     .sufficient
        inc     r10
        jmp     .sell_scan

        ; ── BUY: count resting ask quantity at crossable prices ───────────────
        ; Asks sorted ascending, walk from index 0 while ask.price <= limit
.buy_side:
        mov     r9,  [rel ob_ask_count]
        test    r9, r9
        jz      .insufficient
        xor     r10, r10
        xor     rdx, rdx
        lea     rax, [rel ob_ask_levels]
.buy_scan:
        cmp     r10, r9
        jge     .check
        mov     rcx, r10
        shl     rcx, L_SHIFT
        add     rcx, rax
        movzx   r8d, byte [rdi + O_TYPE]
        cmp     r8d, TYPE_MARKET
        je      .buy_accum
        movsd   xmm1, [rcx + L_PRICE]
        ucomisd xmm1, xmm0                  ; ask.price vs limit_buy
        ja      .check                      ; ask above our ceiling → no more crosses
.buy_accum:
        mov     r8d, dword [rdi + O_QTY]
        add     rdx, qword [rcx + L_TOTAL_QTY]
        cmp     rdx, r8
        jge     .sufficient
        inc     r10
        jmp     .buy_scan

.check:
        ; Loop ended without accumulating enough
        mov     r8d, dword [rdi + O_QTY]
        cmp     rdx, r8
        jge     .sufficient
.insufficient:
        xor     eax, eax
        ret
.sufficient:
        mov     eax, 1
        ret


; =============================================================================
; ob_add_order — add order to book, attempt immediate matching
;
; Workflow:
;   1. Allocate pool slot and copy caller's template into it.
;   2. Stamp timestamp_ns.
;   3. Call ob_match_bottom to attempt immediate fill.
;   4. If order is not fully filled and TIF allows resting, insert the
;      remainder into the appropriate price level.
;
; args : rdi = pointer to Order template (copied into pool, not stored as-is)
;        rsi = pointer to MatchingResult output
;        rdx = pointer to Execution array output
; ret  : rax = pool index of resting order (FREE_SENTINEL on failure or
;              if order was fully filled / cancelled by TIF)
; =============================================================================
ob_add_order:
        push    r12
        push    r13
        push    r14
        push    r15
        push    rbx

        mov     r12, rdi           ; template pointer
        mov     r13, rsi           ; result pointer
        mov     r14, rdx           ; exec array pointer

        ; Allocate slot
        call    _alloc_order
        test    rax, rax
        jz      .add_fail

        mov     r15, rax           ; r15 = allocated slot pointer

        ; Timestamp
        push    r15
        call    _timestamp_ns      ; rax = ns
        pop     r15
        mov     [r15 + O_TS_NS], rax

        ; Copy template into slot (64 bytes = 4 × 16-byte)
        movdqu  xmm0, [r12]
        movdqu  xmm1, [r12+16]
        movdqu  xmm2, [r12+32]
        movdqu  xmm3, [r12+48]
        movdqu  [r15],    xmm0
        movdqu  [r15+16], xmm1
        movdqu  [r15+32], xmm2    ; overwrites O_TS_NS (+32) with template value
        movdqu  [r15+48], xmm3
        ; Restore our timestamp (template had whatever caller put at +32)
        mov     rax, [r15 + O_TS_NS]   ; if caller didn't set it, zero
        call    _timestamp_ns
        mov     [r15 + O_TS_NS], rax

        ; Record orig_qty = qty
        mov     eax, [r15 + O_QTY]
        mov     [r15 + O_ORIG_QTY], eax

        ; Make O_NEXT a clean sentinel
        mov     dword [r15 + O_NEXT], FREE_SENTINEL

        inc     qword [rel ob_seq]

        ; ── FOK pre-flight ────────────────────────────────────────────────────
        ; True FOK semantics: if we cannot fill the ENTIRE quantity we must
        ; reject the whole order *before* executing any trades.  Doing it after
        ; a partial fill would leave the book in a modified state with no way to
        ; roll back the already-consumed resting orders.
        movzx   ecx, byte [r15 + O_TIF]
        cmp     ecx, TIF_FOK
        jne     .skip_fok_preflight
        mov     rdi, r15
        call    _fok_available          ; eax = 1 (ok) or 0 (reject)
        test    eax, eax
        jz      .fok_reject
.skip_fok_preflight:

        ; Attempt immediate matching
        mov     rdi, r15
        mov     rsi, r13
        mov     rdx, r14
        call    ob_match_bottom

        ; If fully filled, pool slot was freed by matching engine; return sentinel
        mov     eax, [r13 + R_STATUS]
        cmp     eax, STATUS_FILLED
        je      .add_filled

        ; Check TIF: IOC and FOK cancel any remainder
        movzx   ecx, byte [r15 + O_TIF]
        cmp     ecx, TIF_IOC
        je      .add_cancel_remainder
        cmp     ecx, TIF_FOK
        je      .add_cancel_remainder

        ; Update O_QTY to reflect remaining quantity
        mov     eax, [r13 + R_REMAIN_QTY]
        mov     [r15 + O_QTY], eax

        ; Compute pool index of r15
        mov     rdi, r15
        call    _pool_idx          ; eax = pool index
        mov     ebx, eax           ; ebx = pool index (saved for return)

        ; Insert remainder into the correct price level
        movzx   ecx, byte [r15 + O_SIDE]
        cmp     ecx, SIDE_BUY
        je      .rest_buy

        ; ── REST SELL ────────────────────────────────────────────────────────
        movsd   xmm0, [r15 + O_PRICE]
        call    _ask_find          ; rax = index, rdx = found?
        push    rdx                ; save found flag
        push    rax                ; save index
        test    rdx, rdx
        jnz     .ask_level_found

        ; New price level
        mov     rdi, rax
        call    _ask_open_slot     ; rax = new level pointer
        test    rax, rax
        jz      .rest_fail
        movsd   xmm0, [r15 + O_PRICE]
        movsd   [rax + L_PRICE], xmm0
        jmp     .ask_add_order

.ask_level_found:
        pop     rax                ; index
        push    rax
        shl     rax, L_SHIFT
        lea     rdx, [rel ob_ask_levels]
        add     rax, rdx           ; rax = level pointer

.ask_add_order:
        ; rax = level pointer, ebx = pool index, ecx = remaining qty
        ; _level_add_order clobbers rdx; save r15, ebx
        push    r15
        push    rbx
        mov     ecx, dword [r15 + O_QTY]   ; zero-extends to rcx
        call    _level_add_order            ; rax=level_ptr, rbx=order_idx, rcx=qty
        pop     rbx
        pop     r15
        pop     rax                ; pop (index or found) — align stack
        pop     rdx                ; pop found flag — align stack
        mov     eax, ebx           ; return pool index
        jmp     .add_done

.rest_buy:
        ; ── REST BUY ─────────────────────────────────────────────────────────
        movsd   xmm0, [r15 + O_PRICE]
        call    _bid_find          ; rax = index, rdx = found?
        push    rdx
        push    rax
        test    rdx, rdx
        jnz     .bid_level_found

        mov     rdi, rax
        call    _bid_open_slot
        test    rax, rax
        jz      .rest_fail
        movsd   xmm0, [r15 + O_PRICE]
        movsd   [rax + L_PRICE], xmm0
        jmp     .bid_add_order

.bid_level_found:
        pop     rax
        push    rax
        shl     rax, L_SHIFT
        lea     rdx, [rel ob_bid_levels]
        add     rax, rdx

.bid_add_order:
        mov     ecx, dword [r15 + O_QTY]    ; zero-extends to rcx
        push    r15
        push    rbx
        call    _level_add_order
        pop     rbx
        pop     r15
        pop     rax
        pop     rdx
        mov     eax, ebx
        jmp     .add_done

.rest_fail:
        add     rsp, 16            ; clean pushed rax/rdx
        jmp     .add_cancel_remainder

.add_filled:
        mov     eax, FREE_SENTINEL
        jmp     .add_done

.add_cancel_remainder:
        ; Free the pool slot (remainder is not resting)
        mov     rdi, r15
        call    _free_order
        mov     eax, FREE_SENTINEL
        jmp     .add_done

.fok_reject:
        ; FOK pre-flight failed: not enough crossable liquidity.
        ; Populate result as REJECTED without touching the book at all.
        mov     rax, [r15 + O_ID_LO]
        mov     [r13 + R_ID_LO], rax
        mov     rax, [r15 + O_ID_HI]
        mov     [r13 + R_ID_HI], rax
        mov     eax, [r15 + O_QTY]
        mov     [r13 + R_ORIG_QTY],   eax
        mov     [r13 + R_REMAIN_QTY], eax
        mov     dword [r13 + R_FILLED_QTY], 0
        mov     dword [r13 + R_STATUS], STATUS_REJECTED
        pxor    xmm0, xmm0
        movsd   [r13 + R_AVG_PRICE], xmm0
        ; Free the pre-allocated slot — book is untouched
        mov     rdi, r15
        call    _free_order
        mov     eax, FREE_SENTINEL
        jmp     .add_done

.add_fail:
        mov     eax, FREE_SENTINEL

.add_done:
        pop     rbx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret


; =============================================================================
; ob_cancel_order — remove an order from the book by UUID
;
; Scans all bid and ask levels.  O(N_orders) worst-case.
; For O(1) cancel, augment with an id→index hash table (not shown here).
;
; args : rdi = id_lo   rsi = id_hi
; ret  : rax = 1 if found and cancelled, 0 if not found
; =============================================================================
ob_cancel_order:
        push    r12
        push    r13
        push    r14
        push    r15

        mov     r12, rdi           ; id_lo
        mov     r13, rsi           ; id_hi

        ; Search bid side
        lea     r14, [rel ob_bid_levels]
        mov     r15, [rel ob_bid_count]
        call    .scan
        test    eax, eax
        jnz     .found

        ; Search ask side
        lea     r14, [rel ob_ask_levels]
        mov     r15, [rel ob_ask_count]
        call    .scan
        test    eax, eax
        jnz     .found

        xor     eax, eax           ; not found
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret

.found:
        mov     eax, 1
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret

; ─── .scan: walk r14=levels, r15=count; search for (r12, r13) ─────────────
; ret: eax = 1 found+removed, 0 not found
; Uses rcx rdx r8 r9 rbx
.scan:
        push    rbx
        push    rbp

        xor     rbx, rbx           ; level index

.scan_level_loop:
        cmp     rbx, r15
        jge     .scan_not_found

        mov     rax, rbx
        shl     rax, L_SHIFT
        add     rax, r14           ; rax = &levels[rbx]
        mov     rcx, rax           ; rcx = level ptr (saved across order walk)

        mov     r8d, [rcx + L_HEAD]
        mov     r9d, FREE_SENTINEL ; prev_idx = sentinel

.scan_order_loop:
        cmp     r8d, FREE_SENTINEL
        je      .scan_next_level

        mov     edi, r8d
        push    r8
        push    r9
        push    rcx
        call    _pool_ptr
        pop     rcx
        pop     r9
        pop     r8
        mov     rbp, rax           ; rbp = order ptr

        ; Compare ids
        mov     rdx, [rbp + O_ID_LO]
        cmp     rdx, r12
        jne     .scan_advance
        mov     rdx, [rbp + O_ID_HI]
        cmp     rdx, r13
        jne     .scan_advance

        ; ── Found — unlink from intrusive list ───────────────────────────────
        mov     edx, [rbp + O_NEXT]   ; edx = next_idx

        cmp     r9d, FREE_SENTINEL
        je      .remove_head_node
        ; prev.next = cur.next
        mov     edi, r9d
        push    r8
        push    r9
        push    rcx
        push    rdx
        call    _pool_ptr
        pop     rdx
        pop     rcx
        pop     r9
        pop     r8
        mov     [rax + O_NEXT], edx
        jmp     .update_level_cancel
.remove_head_node:
        mov     [rcx + L_HEAD], edx

.update_level_cancel:
        ; Update level totals
        mov     eax, dword [rbp + O_QTY]    ; zero-extends to rax
        sub     [rcx + L_TOTAL_QTY],   rax
        sub     [rcx + L_VISIBLE_QTY], rax
        dec     dword [rcx + L_ORDER_COUNT]

        ; Free the order
        mov     rdi, rbp
        push    rbx
        push    r14
        push    r15
        push    rcx
        call    _free_order
        pop     rcx
        pop     r15
        pop     r14
        pop     rbx

        ; Collapse level if empty
        cmp     dword [rcx + L_ORDER_COUNT], 0
        jne     .cancel_done

        ; Determine which side to collapse (r14 tells us)
        lea     rdx, [rel ob_bid_levels]
        cmp     r14, rdx
        jne     .collapse_ask_side
        mov     rdi, rbx            ; level index
        push    r14
        push    r15
        call    _bid_collapse
        pop     r15
        pop     r14
        jmp     .cancel_done
.collapse_ask_side:
        mov     rdi, rbx
        push    r14
        push    r15
        call    _ask_collapse
        pop     r15
        pop     r14

.cancel_done:
        inc     qword [rel ob_seq]
        mov     eax, 1
        pop     rbp
        pop     rbx
        ret

.scan_advance:
        mov     r9d, r8d
        mov     r8d, [rbp + O_NEXT]
        jmp     .scan_order_loop

.scan_next_level:
        inc     rbx
        jmp     .scan_level_loop

.scan_not_found:
        xor     eax, eax
        pop     rbp
        pop     rbx
        ret


; =============================================================================
; _start — standalone example (no libc; uses raw write(2) syscall)
;
; Replicates the Swift example() scenario:
;   1.  Add BUY  LIMIT 100 @ 150.00
;   2.  Add SELL LIMIT 100 @ 150.50
;   3.  Print best bid / ask / spread / mid
;   4.  Execute MARKET BUY qty=50
;   5.  Print fill status
; =============================================================================
_start:
        call    ob_init

        lea     rdi, [rel s_banner]
        call    _puts

        ; Stack layout (downward from rsp after alignment)
        ;   [rsp +  0  ..  63]: order_a  (bid template)
        ;   [rsp + 64  .. 127]: order_b  (ask template)
        ;   [rsp + 128 .. 191]: order_c  (market buy template)
        ;   [rsp + 192 .. 239]: MatchingResult (48 bytes)
        ;   [rsp + 240 .. 240+MAX_EXECUTIONS*E_SIZE-1]: Execution array
        %define EXEC_ARRAY_SIZE  (MAX_EXECUTIONS * E_SIZE)
        sub     rsp, 3*O_SIZE + R_SIZE + EXEC_ARRAY_SIZE

        %define T_A   rsp
        %define T_B   rsp + O_SIZE
        %define T_C   rsp + O_SIZE*2
        %define RESULT rsp + O_SIZE*3
        %define EXECS  rsp + O_SIZE*3 + R_SIZE

        ; Zero entire stack frame
        mov     rcx, (3*O_SIZE + R_SIZE + EXEC_ARRAY_SIZE) / 8
        lea     rdi, [rsp]
        xor     eax, eax
        rep     stosq

        ; ── ORDER A: BUY LIMIT 100 @ 150.00 ───────────────────────────────────
        ; 150.00 IEEE 754 double = 0x4062C00000000000
        mov     rax, 0xA1A1A1A1A1A1A1A1     ; 64-bit imm must go through register
        mov     [T_A + O_ID_LO], rax
        mov     qword [T_A + O_ID_HI], 0
        mov     rax, 0x4062C00000000000
        mov     [T_A + O_PRICE], rax
        mov     dword [T_A + O_QTY], 100
        mov     byte  [T_A + O_SIDE], SIDE_BUY
        mov     byte  [T_A + O_TYPE], TYPE_LIMIT
        mov     byte  [T_A + O_TIF],  TIF_GTC
        mov     dword [T_A + O_PRIORITY], 1
        mov     dword [T_A + O_NEXT], -1    ; FREE_SENTINEL = 0xFFFFFFFF

        lea     rdi, [T_A]
        lea     rsi, [RESULT]
        lea     rdx, [EXECS]
        call    ob_add_order

        ; ── ORDER B: SELL LIMIT 100 @ 150.50 ──────────────────────────────────
        ; 150.50 IEEE 754 double = 0x4062D00000000000
        mov     rax, 0xB2B2B2B2B2B2B2B2
        mov     [T_B + O_ID_LO], rax
        mov     qword [T_B + O_ID_HI], 0
        mov     rax, 0x4062D00000000000
        mov     [T_B + O_PRICE], rax
        mov     dword [T_B + O_QTY], 100
        mov     byte  [T_B + O_SIDE], SIDE_SELL
        mov     byte  [T_B + O_TYPE], TYPE_LIMIT
        mov     byte  [T_B + O_TIF],  TIF_GTC
        mov     dword [T_B + O_PRIORITY], 1
        mov     dword [T_B + O_NEXT], -1

        lea     rdi, [T_B]
        lea     rsi, [RESULT]
        lea     rdx, [EXECS]
        call    ob_add_order

        ; ── Print book ─────────────────────────────────────────────────────────
        lea     rdi, [rel s_bid]
        call    _puts_no_nl
        call    ob_best_bid
        call    _print_f64

        lea     rdi, [rel s_ask]
        call    _puts_no_nl
        call    ob_best_ask
        call    _print_f64

        lea     rdi, [rel s_spread]
        call    _puts_no_nl
        call    ob_spread
        call    _print_f64

        lea     rdi, [rel s_mid]
        call    _puts_no_nl
        call    ob_mid_price
        call    _print_f64

        ; ── ORDER C: MARKET BUY qty=50 ────────────────────────────────────────
        ; Zero the result first
        lea     rdi, [RESULT]
        mov     ecx, R_SIZE / 8
        xor     eax, eax
        rep     stosq

        mov     rax, 0xC3C3C3C3C3C3C3C3
        mov     [T_C + O_ID_LO], rax
        mov     qword [T_C + O_ID_HI], 0
        mov     qword [T_C + O_PRICE], 0       ; 0.0 = market
        mov     dword [T_C + O_QTY],   50
        mov     byte  [T_C + O_SIDE],  SIDE_BUY
        mov     byte  [T_C + O_TYPE],  TYPE_MARKET
        mov     byte  [T_C + O_TIF],   TIF_IOC
        mov     dword [T_C + O_PRIORITY], 1
        mov     dword [T_C + O_NEXT], -1

        lea     rdi, [T_C]
        lea     rsi, [RESULT]
        lea     rdx, [EXECS]
        call    ob_match_bottom

        ; Print result
        lea     rdi, [rel s_match]
        call    _puts_no_nl

        mov     eax, [RESULT + R_STATUS]
        cmp     eax, STATUS_FILLED
        je      .pf
        cmp     eax, STATUS_PARTIAL
        je      .pp
        cmp     eax, STATUS_REJECTED
        je      .pr
        lea     rdi, [rel s_pending]
        jmp     .ps
.pf:    lea     rdi, [rel s_filled]   ; jmp
        jmp     .ps
.pp:    lea     rdi, [rel s_partial]
        jmp     .ps
.pr:    lea     rdi, [rel s_rejected]
.ps:    call    _puts_no_nl

        lea     rdi, [rel s_filled_q]
        call    _puts_no_nl
        mov     eax, [RESULT + R_FILLED_QTY]
        call    _print_u32

        lea     rdi, [rel s_avg_px]
        call    _puts_no_nl
        movsd   xmm0, [RESULT + R_AVG_PRICE]
        call    _print_f64

        lea     rdi, [rel s_done]
        call    _puts

        add     rsp, 3*O_SIZE + R_SIZE + EXEC_ARRAY_SIZE

        ; ── run the three targeted tests ──────────────────────────────────────
        call    ob_init
        call    _test_cancel

        call    ob_init
        call    _test_fok

        call    ob_init
        call    _test_pool_exhaust

        mov     eax, SYS_exit
        xor     edi, edi
        syscall


; =============================================================================
; _test_cancel — ob_cancel_order: UUID scan-and-unlink
;
; Scenario:
;   1. Add one SELL LIMIT order (UUID 0xCAFEBEEFCAFEBEEF / 0) at 300.00
;      — no bids exist, so it rests on the ask side
;   2. Verify ask_count == 1
;   3. Cancel by UUID
;   4. Verify cancel() returned 1  AND  ask_count == 0
; =============================================================================
_test_cancel:
        push    r12
        push    r13
        push    r14
        push    r15
        push    rbx

        lea     rdi, [rel s_t_cancel]
        call    _puts_no_nl

        ; Stack frame: Order template (64) + Result (48) + small exec buf (8×E_SIZE=192)
        ; Total = 304 bytes → round to 304 (divisible by 16 ✓)
        %define TC_FRAME  304
        %define TC_ORD    rsp
        %define TC_RES    rsp + O_SIZE
        %define TC_EXC    rsp + O_SIZE + R_SIZE
        sub     rsp, TC_FRAME
        ; Zero the frame
        lea     rdi, [rsp]
        xor     eax, eax
        mov     ecx, TC_FRAME / 8
        rep     stosq

        ; Build SELL LIMIT: qty=75  price=300.00  UUID=(0xCAFEBEEFCAFEBEEF, 0)
        ; 300.0 IEEE 754 = 0x4072C00000000000
        mov     rax, 0xCAFEBEEFCAFEBEEF
        mov     [TC_ORD + O_ID_LO], rax
        mov     qword [TC_ORD + O_ID_HI], 0
        mov     rax, 0x4072C00000000000
        mov     [TC_ORD + O_PRICE], rax
        mov     dword [TC_ORD + O_QTY],      75
        mov     byte  [TC_ORD + O_SIDE],     SIDE_SELL
        mov     byte  [TC_ORD + O_TYPE],     TYPE_LIMIT
        mov     byte  [TC_ORD + O_TIF],      TIF_GTC
        mov     dword [TC_ORD + O_PRIORITY], 1
        mov     dword [TC_ORD + O_NEXT],     -1

        lea     rdi, [TC_ORD]
        lea     rsi, [TC_RES]
        lea     rdx, [TC_EXC]
        call    ob_add_order

        ; print ask_count (should be 1)
        lea     rdi, [rel s_ask_count]
        call    _puts_no_nl
        mov     eax, dword [rel ob_ask_count]
        call    _print_u32

        ; Cancel by UUID
        mov     rdi, 0xCAFEBEEFCAFEBEEF
        xor     rsi, rsi
        call    ob_cancel_order
        mov     r12, rax               ; save return value (1 = found)

        ; print cancel return
        lea     rdi, [rel s_cancel_ret]
        call    _puts_no_nl
        mov     eax, r12d
        call    _print_u32

        ; print ask_count (should be 0)
        lea     rdi, [rel s_ask_count]
        call    _puts_no_nl
        mov     eax, dword [rel ob_ask_count]
        call    _print_u32

        ; PASS if cancel() == 1 AND ask_count == 0
        cmp     r12d, 1
        jne     .tc_fail
        cmp     qword [rel ob_ask_count], 0
        jne     .tc_fail
        lea     rdi, [rel s_pass]
        call    _puts_no_nl
        jmp     .tc_done
.tc_fail:
        lea     rdi, [rel s_fail]
        call    _puts_no_nl
.tc_done:
        add     rsp, TC_FRAME
        pop     rbx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret


; =============================================================================
; _test_fok — FOK pre-flight rejects when resting qty < order qty
;
; Scenario:
;   1. Add SELL LIMIT qty=30 @ 200.00 (rests; no bids)
;   2. Submit FOK BUY LIMIT qty=50 @ 200.00
;      — _fok_available sees only 30 crossable; pre-flight rejects before
;        executing any trade
;   3. Expect: status == REJECTED, filled_qty == 0, remain_qty == 50
;   4. Expect: ask side still has qty=30 (book untouched)
; =============================================================================
_test_fok:
        push    r12
        push    r13
        push    r14
        push    r15
        push    rbx

        lea     rdi, [rel s_t_fok]
        call    _puts_no_nl

        %define TF_FRAME  304
        %define TF_ORD    rsp
        %define TF_RES    rsp + O_SIZE
        %define TF_EXC    rsp + O_SIZE + R_SIZE
        sub     rsp, TF_FRAME
        lea     rdi, [rsp]
        xor     eax, eax
        mov     ecx, TF_FRAME / 8
        rep     stosq

        ; Add SELL LIMIT qty=30 @ 200.00 — will rest
        ; 200.0 IEEE 754 = 0x4069000000000000
        mov     rax, 0xAAAA000000000001
        mov     [TF_ORD + O_ID_LO], rax
        mov     qword [TF_ORD + O_ID_HI], 0
        mov     rax, 0x4069000000000000
        mov     [TF_ORD + O_PRICE], rax
        mov     dword [TF_ORD + O_QTY],      30
        mov     byte  [TF_ORD + O_SIDE],     SIDE_SELL
        mov     byte  [TF_ORD + O_TYPE],     TYPE_LIMIT
        mov     byte  [TF_ORD + O_TIF],      TIF_GTC
        mov     dword [TF_ORD + O_PRIORITY], 1
        mov     dword [TF_ORD + O_NEXT],     -1

        lea     rdi, [TF_ORD]
        lea     rsi, [TF_RES]
        lea     rdx, [TF_EXC]
        call    ob_add_order            ; rests, no fills

        ; Zero result before the FOK attempt
        lea     rdi, [TF_RES]
        xor     eax, eax
        mov     ecx, R_SIZE / 8
        rep     stosq

        ; Zero template for reuse as FOK BUY
        lea     rdi, [TF_ORD]
        xor     eax, eax
        mov     ecx, O_SIZE / 8
        rep     stosq

        ; Build FOK BUY LIMIT qty=50 @ 200.00
        mov     rax, 0xBBBB000000000002
        mov     [TF_ORD + O_ID_LO], rax
        mov     qword [TF_ORD + O_ID_HI], 0
        mov     rax, 0x4069000000000000     ; 200.00
        mov     [TF_ORD + O_PRICE], rax
        mov     dword [TF_ORD + O_QTY],      50     ; want 50, only 30 available
        mov     byte  [TF_ORD + O_SIDE],     SIDE_BUY
        mov     byte  [TF_ORD + O_TYPE],     TYPE_LIMIT
        mov     byte  [TF_ORD + O_TIF],      TIF_FOK
        mov     dword [TF_ORD + O_PRIORITY], 1
        mov     dword [TF_ORD + O_NEXT],     -1

        lea     rdi, [TF_ORD]
        lea     rsi, [TF_RES]
        lea     rdx, [TF_EXC]
        call    ob_add_order

        ; Print status
        lea     rdi, [rel s_match]
        call    _puts_no_nl
        mov     eax, [TF_RES + R_STATUS]
        cmp     eax, STATUS_REJECTED
        je      .tf_print_rej
        cmp     eax, STATUS_PARTIAL
        je      .tf_print_par
        cmp     eax, STATUS_FILLED
        je      .tf_print_fil
        lea     rdi, [rel s_pending]
        jmp     .tf_print_done
.tf_print_rej: lea rdi, [rel s_rejected]  ; jmp
        jmp     .tf_print_done
.tf_print_par: lea rdi, [rel s_partial]
        jmp     .tf_print_done
.tf_print_fil: lea rdi, [rel s_filled]
.tf_print_done: call _puts_no_nl

        lea     rdi, [rel s_filled_q]
        call    _puts_no_nl
        mov     eax, [TF_RES + R_FILLED_QTY]
        call    _print_u32

        lea     rdi, [rel s_remain_qty]
        call    _puts_no_nl
        mov     eax, [TF_RES + R_REMAIN_QTY]
        call    _print_u32

        ; Also show that ask side still has qty=30 (book is pristine)
        lea     rdi, [rel s_ask_count]
        call    _puts_no_nl
        mov     eax, dword [rel ob_ask_count]
        call    _print_u32

        ; PASS: status==REJECTED, filled==0, ask_count==1 (level still there)
        cmp     dword [TF_RES + R_STATUS],     STATUS_REJECTED
        jne     .tf_fail
        cmp     dword [TF_RES + R_FILLED_QTY], 0
        jne     .tf_fail
        cmp     qword [rel ob_ask_count], 1
        jne     .tf_fail
        lea     rdi, [rel s_pass]
        call    _puts_no_nl
        jmp     .tf_done
.tf_fail:
        lea     rdi, [rel s_fail]
        call    _puts_no_nl
.tf_done:
        add     rsp, TF_FRAME
        pop     rbx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret


; =============================================================================
; _test_pool_exhaust — verify pool returns null on the 65537th allocation
;
; Scenario:
;   Directly call _alloc_order in a tight loop until the free list is empty
;   (65536 iterations).  The 65537th call must return 0 (pool exhausted),
;   which ob_add_order surfaces as FREE_SENTINEL to callers.
;   We do NOT call ob_add_order here — it involves matching overhead and would
;   also try to rest each order, hitting the price-level limit first.
;   _alloc_order is the single-responsibility primitive being tested.
; =============================================================================
_test_pool_exhaust:
        push    r12
        push    r13
        push    rbx

        lea     rdi, [rel s_t_pool]
        call    _puts_no_nl

        ; Drain the pool
        xor     r12, r12                ; count of successful allocs
        mov     r13d, MAX_ORDERS

.exhaust_loop:
        cmp     r12, r13
        jge     .exhaust_done
        call    _alloc_order
        test    rax, rax
        jz      .exhaust_done          ; pool unexpectedly empty early → fail
        inc     r12
        jmp     .exhaust_loop

.exhaust_done:
        ; Print how many we placed
        lea     rdi, [rel s_placed]
        call    _puts_no_nl
        mov     eax, r12d
        call    _print_u32

        ; One more allocation — must return 0
        call    _alloc_order
        lea     rdi, [rel s_alloc65537]
        call    _puts_no_nl
        test    rax, rax
        jnz     .pe_nonzero
        lea     rdi, [rel s_null_ptr]
        call    _puts_no_nl
        jmp     .pe_check
.pe_nonzero:
        lea     rdi, [rel s_nonzero]
        call    _puts_no_nl

.pe_check:
        ; PASS: placed exactly MAX_ORDERS AND final alloc returned 0
        cmp     r12, r13
        jne     .pe_fail
        test    rax, rax
        jnz     .pe_fail
        lea     rdi, [rel s_pass]
        call    _puts_no_nl
        jmp     .pe_done
.pe_fail:
        lea     rdi, [rel s_fail]
        call    _puts_no_nl
.pe_done:
        pop     rbx
        pop     r13
        pop     r12
        ret


; =============================================================================
; I/O helpers — no libc, direct write(2) syscall
; =============================================================================

; _strlen : rdi = str  →  rax = length
_strlen:
        xor     eax, eax
.L:     cmp     byte [rdi + rax], 0
        je      .D
        inc     eax
        jmp     .L
.D:     ret

; _puts : rdi = null-terminated string  →  writes str + LF
_puts:
        push    rdi
        call    _strlen
        mov     rdx, rax
        pop     rsi
        mov     eax, SYS_write
        mov     edi, STDOUT_FD
        syscall
        lea     rsi, [rel s_newline]
        mov     eax, SYS_write
        mov     edi, STDOUT_FD
        mov     edx, 1
        syscall
        ret

; _puts_no_nl : rdi = null-terminated string  →  writes str without LF
_puts_no_nl:
        push    rdi
        call    _strlen
        mov     rdx, rax
        pop     rsi
        mov     eax, SYS_write
        mov     edi, STDOUT_FD
        syscall
        ret

; _print_u32 : eax = unsigned integer  →  writes decimal digits + LF
_print_u32:
        lea     rdi, [rel _print_buf + 31]
        mov     byte [rdi], 10          ; LF at end
        dec     rdi
        mov     byte [rdi], 0           ; null (not used by write, but safe)
        ; sentinel
        mov     ecx, eax
        mov     r8d, 10
.pu_loop:
        xor     edx, edx
        mov     eax, ecx
        div     r8d
        add     dl, '0'
        dec     rdi
        mov     [rdi], dl
        mov     ecx, eax
        test    eax, eax
        jnz     .pu_loop
        ; write from rdi to _print_buf+31 (inclusive of LF)
        lea     rsi, [rdi]
        lea     rdx, [rel _print_buf + 32]
        sub     rdx, rsi
        mov     eax, SYS_write
        mov     edi, STDOUT_FD
        syscall
        ret

; _print_f64 : xmm0 = double  →  prints "NNNN.NN\n"
; Converts to integer centiprice (×100), then formats as X.YY
_print_f64:
        push    rbx
        ; Check for NaN (ucomisd with itself sets PF if NaN)
        ucomisd xmm0, xmm0
        jp      .nan

        mulsd   xmm0, [rel k_hundred]  ; scale to centiprice
        cvttsd2si rax, xmm0             ; truncate to integer

        ; Format into _print_buf (right-to-left)
        lea     rdi, [rel _print_buf + 31]
        mov     byte [rdi], 10          ; LF
        dec     rdi

        ; Cents digit (last two digits after decimal point)
        mov     rbx, 10
        xor     rdx, rdx
        div     rbx
        add     dl, '0'
        mov     [rdi], dl
        dec     rdi
        xor     rdx, rdx
        div     rbx
        add     dl, '0'
        mov     [rdi], dl
        dec     rdi
        mov     byte [rdi], '.'
        dec     rdi

        ; Integer part
        test    rax, rax
        jnz     .int_loop
        mov     byte [rdi], '0'
        dec     rdi
        jmp     .emit
.int_loop:
        test    rax, rax
        jz      .emit
        xor     rdx, rdx
        div     rbx
        add     dl, '0'
        mov     [rdi], dl
        dec     rdi
        jmp     .int_loop

.emit:
        inc     rdi
        lea     rsi, [rdi]
        lea     rdx, [rel _print_buf + 32]
        sub     rdx, rsi
        mov     eax, SYS_write
        mov     edi, STDOUT_FD
        syscall
        pop     rbx
        ret

.nan:
        lea     rdi, [rel s_none]
        call    _puts_no_nl
        pop     rbx
        ret

; =============================================================================
; end of hft_orderbook.asm
; =============================================================================
