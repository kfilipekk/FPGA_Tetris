# FPGA Speculative Order Gateway

A cut-through trading engine on a Tang Nano 9K (GW1NR-9C). It reads NASDAQ ITCH 5.0 add orders and starts sending an OUCH 4.2 buy order as soon as the symbol matches, before the price or the frame check have arrived. If the price is over the limit, the feed frame is corrupt or the risk gate says no, the order's FCS goes out inverted and the far end drops it. Open source flow: yosys, nextpnr, apicula, cocotb, SymbiYosys.

## Results

On the board:

| Run | Result |
|-----|--------|
| NASDAQ ITCH 5.0, 30 Jan 2019 from 04:00 | 46,406 messages in 32 s at 1 Mbaud, every order matches the model |
| The 1,459 AAPL sells among them | 78 committed, 723 stomped on price, 658 by the rate limiter |
| Synthetic feed with cut and corrupted frames | 5,000 messages, 0 mismatches |
| SCK edge to order start bit, 24 MHz analyser | 208-250 ns (6 clocks, ±1 sample) |

From simulation and place and route:

| | |
|-|-|
| Symbol match to first order byte | 2 clocks |
| Last feed byte to verdict | 3 clocks |
| Fabric | 2675 LUT4 (30%), 1185 DFF, 2 DSP, 51 MHz (27 MHz needed) |
| Tests | 4 formal proofs, 34 cocotb tests, 15 host tests |

## How It Works

The order needs the price at byte 28 and the verdict at byte 49. The feed gives them 4 and 8 bytes after the trigger, so the order can start on the symbol. A late verdict or a missing price stomps the frame.

![Speculation](docs/img/speculation.png)

Proven with k-induction:
- **ouch_tx** - 53 bytes every time, and a good FCS only after a commit that beat it
- **itch_parser** - a pass means a full frame, matching header and a correct FCS
- **risk_gate** - nothing while killed or out of limits, at most BURST + 1 orders per REFILL window
- **hft_core** - a good FCS only after a risk grant on a clean frame under the limit

## Layout

- `rtl/` - parser, order builder, risk gate, core, on-chip feed, uart and spi
- `sim/` - cocotb against `host/model.py`
- `formal/` - SymbiYosys
- `host/` - `replay.py` feeds the board, `exchange.py` reads orders, `capture.py` checks analyser captures
- `docs/captures/` - the bench captures

## Building

```bash
./setup.sh
source tools/oss-cad-suite/environment
make            # bitstream
make sim        # cocotb
make formal     # symbiyosys
make flash
```

S1 plays a scripted burst, S2 toggles the kill switch. Feed it from the PC:

```bash
python3 host/replay.py /dev/ttyUSB1 --synthetic 5000
curl -s https://emi.nasdaq.com/ITCH/Nasdaq%20ITCH/01302019.NASDAQ_ITCH50.gz \
    | python3 host/itch_cut.py AAPL 3000 > captures/aapl.itch
python3 host/replay.py /dev/ttyUSB1 --itch captures/aapl.itch --limit 162.80
```

For 1 Mbaud, build with `make PARAMS="chparam -set UART_DIV 27 top"` and pass `--baud 1000000`.

## Logic Analyser

| Ch | Pin | Signal |
|----|-----|--------|
| 0 | 25 | feed_sck |
| 1 | 26 | feed_mosi |
| 2 | 27 | feed_cs_n |
| 3 | 28 | ord_tx |
| 4 | 29 | spec |
| 5 | 30 | risk_ok |
| 6 | 33 | tx_commit |
| 7 | 34 | tx_abort |

```bash
sigrok-cli -d fx2lafw --config samplerate=24m:captureratio=60 --samples 2m --triggers D5=f -o burst.sr
python3 host/capture.py burst.sr --plot burst.png
```

![Burst](docs/img/burst.png)
