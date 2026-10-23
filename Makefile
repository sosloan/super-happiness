CXX      := g++
CXXFLAGS := -std=c++17 -O2 -Wall -Wextra -Wpedantic -I.
LDFLAGS  := -Wl,-z,noexecstack
NASM     := nasm
NASMFLAGS := -f elf64 -g -F dwarf

.PHONY: all clean test standalone

all: market

market: main.o market.o hft_orderbook.o
	$(CXX) $(CXXFLAGS) -o $@ main.o market.o hft_orderbook.o $(LDFLAGS)

main.o: main.cpp market.hpp orderbook.h
	$(CXX) $(CXXFLAGS) -c main.cpp

market.o: market.cpp market.hpp orderbook.h
	$(CXX) $(CXXFLAGS) -c market.cpp

# Rename the assembly demo entry so crt0 owns _start. ob_* stay the engine API.
hft_orderbook.o: hft_orderbook.asm
	$(NASM) $(NASMFLAGS) hft_orderbook.asm -o $@
	objcopy --redefine-sym _start=ob_standalone_start $@

standalone: hft_orderbook.asm
	$(NASM) -f elf64 hft_orderbook.asm -o hft_orderbook_sa.o
	ld -z noexecstack hft_orderbook_sa.o -o hft_orderbook

test: market
	./market

clean:
	rm -f main.o market.o hft_orderbook.o hft_orderbook_sa.o market hft_orderbook
