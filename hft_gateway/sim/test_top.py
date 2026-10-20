import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import model as m
from feed_util import spi_capture, uart_send
from uart_util import recv_byte

DIV = 8      #set in cocotb.mk
HOLD = 4
BURST = 4

V = os.environ.get("VENUE", "nasdaq")
VN = m.VENUES[V]
N = VN["feed"]
FLEN = m.frame_len(V)
SYM, OTHER = VN["symbol"], VN["stocks"][1]
TRIG = 23 if V == "lse" else 32
ORDER = FLEN * 10 * DIV + 2000   #clocks for an order to leave


def px(p4):
    return p4 * VN["scale"]


def add(ref, sym, price, bad=False):
    if V == "lse":
        return m.mitch_add(ref, b"S", 100, int.from_bytes(sym, "big"), price, bad=bad)
    return m.itch_add(ref, b"S", 100, sym, price, bad=bad)


def kind_of(frame):
    if V == "lse":
        return (int.from_bytes(frame[6:14], "little") >> 48) & 0xFF
    return (int.from_bytes(frame[11:19], "big") >> 48) & 0xFF


async def uart_frames(dut, out):
    cur = bytearray()
    while True:
        cur.append(await recv_byte(dut.clk, dut.uart_tx, DIV))
        if len(cur) == FLEN:
            out.append(bytes(cur))
            cur = bytearray()


async def press(dut, btn):
    btn.value = 0
    await ClockCycles(dut.clk, HOLD + 6)
    btn.value = 1
    await ClockCycles(dut.clk, HOLD + 6)


def expected(feed, tokens, kill=False):
    out = []
    for f in feed:
        v = m.verdict(f, tokens=tokens, kill=kill, venue=V)
        if v is not None:
            tokens -= v[1] == ""
            out.append((m.frame_of(v[0], v[1] == ""), v[1]))
    return out, tokens


async def idle(dut):
    dut.btn_s1.value = 1
    dut.btn_s2.value = 1
    dut.uart_rx.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))


@cocotb.test()
async def burst_then_kill(dut):
    await idle(dut)
    feed, orders = [], []
    cocotb.start_soon(spi_capture(dut.clk, dut.feed_sck, dut.feed_mosi, dut.feed_cs_n, feed))
    cocotb.start_soon(uart_frames(dut, orders))

    seen = set()

    async def pins():
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            for name in ("spec", "tx_commit", "tx_abort"):
                if int(getattr(dut, name).value):
                    seen.add(name)
    cocotb.start_soon(pins())

    while len(feed) < 1:
        await ClockCycles(dut.clk, 100)
    await ClockCycles(dut.clk, ORDER)
    await press(dut, dut.btn_s1)
    while len(feed) < 11:
        await ClockCycles(dut.clk, 1000)
    await ClockCycles(dut.clk, ORDER)

    assert [kind_of(f) for f in feed] == [0] + list(range(1, 11))
    want, tokens = expected(feed, BURST)
    assert orders == [w for w, _ in want]
    whys = [w for _, w in want][-9:]
    assert whys[:4] == ["", "price", "fcs", "limits"]
    n = whys[4:].count("")
    assert whys[4:] == [""] * n + ["tokens"] * (5 - n) and n < 5
    assert seen == {"spec", "tx_commit", "tx_abort"}
    await ReadOnly()
    assert int(dut.risk_ok.value) == int(tokens > 0)

    await FallingEdge(dut.clk)
    await press(dut, dut.btn_s2)
    await ReadOnly()
    assert int(dut.risk_ok.value) == 0
    await FallingEdge(dut.clk)
    n_feed, n_orders = len(feed), len(orders)
    await press(dut, dut.btn_s1)
    while len(feed) < n_feed + 10:
        await ClockCycles(dut.clk, 1000)
    await ClockCycles(dut.clk, ORDER)
    want, _ = expected(feed[n_feed:], tokens, kill=True)
    assert orders[n_orders:] == [w for w, _ in want]
    assert all(m.check_frame(f, V) == "stomped" for f in orders[n_orders:])


@cocotb.test()
async def pin_latency(dut):
    await idle(dut)
    await ClockCycles(dut.clk, 2)
    await press(dut, dut.btn_s2)    #kill off
    await FallingEdge(dut.clk)
    await press(dut, dut.btn_s1)
    edges, start, synced = [], None, False
    cyc, last_sck, last_cs, last_tx = 0, 0, 0, 1
    while start is None:
        await RisingEdge(dut.clk)
        await ReadOnly()
        cyc += 1
        s, c, tx = int(dut.feed_sck.value), int(dut.feed_cs_n.value), int(dut.uart_tx.value)
        if c == 0 and last_cs == 1:
            edges, synced = [], True
        if c == 0 and s == 1 and last_sck == 0:
            edges.append(cyc)
        if synced and tx == 0 and last_tx == 1 and len(edges) >= TRIG * 8:
            start = cyc
        last_sck, last_cs, last_tx = s, c, tx
    lat = start - edges[TRIG * 8 - 1]
    dut._log.info("sck edge to start bit: %d clocks, %.0f ns at 27 MHz", lat, lat * 1e9 / 27e6)
    assert lat == 6


@cocotb.test()
async def host_feed(dut):
    await idle(dut)
    feed, orders = [], []
    quiet = 0
    while quiet < 2 * ORDER:
        await RisingEdge(dut.clk)
        quiet = quiet + 1 if int(dut.feed_cs_n.value) else 0
    cocotb.start_soon(spi_capture(dut.clk, dut.feed_sck, dut.feed_mosi, dut.feed_cs_n, feed))
    cocotb.start_soon(uart_frames(dut, orders))
    tokens = tokens0 = int(dut.u_core.u_risk.tokens.value)
    btn_kill = bool(int(dut.u_s2.state.value))

    lim = px(1600000)
    msgs = [
        m.config(OTHER, lim, kill=False),
        add(1, OTHER, px(1550000)),                          #good
        add(2, OTHER, px(1650000)),                          #over the new limit
        add(3, SYM, px(1490000)),                            #old symbol, ignored
        add(4, OTHER, px(1550000), bad=True),                #corrupt
        m.config(b"CORRUPT!", 1, kill=True)[:-1] + b"\x00",  #bad fcs, ignored
        add(5, OTHER, px(1500000)),                          #good
        m.config(OTHER, lim, kill=True),
        add(6, OTHER, px(1500000)),                          #killed
    ]
    for x in msgs:
        await uart_send(dut.clk, dut.uart_rx, m.block(x), DIV)
        await ClockCycles(dut.clk, ORDER)
    want = []
    kill = False
    for x in msgs:
        if x[0:1] == b"C":
            if x == m.config(OTHER, lim, kill=True):
                kill = True
            continue
        v = m.verdict(x, symbol=OTHER, limit=lim, tokens=tokens, kill=kill or btn_kill, venue=V)
        if v is not None:
            tokens -= v[1] == ""
            want.append(m.frame_of(v[0], v[1] == ""))
    assert orders == want
    if tokens0 >= 2 and not btn_kill:
        assert [m.check_frame(f, V) for f in want] == \
            ["good", "stomped", "stomped", "good", "stomped"]
    assert len(feed) == 0
    assert int(dut.u_cfg.symbol.value) == int.from_bytes(OTHER, "big")

    blk = m.block(add(7, OTHER, px(1500000)))
    cut = 2 + N + 2
    await uart_send(dut.clk, dut.uart_rx, blk[:cut] + blk[cut + 1:], DIV)   #one fcs byte short
    await ClockCycles(dut.clk, 40000)
    await uart_send(dut.clk, dut.uart_rx, m.block(m.config(OTHER, lim)), DIV)
    await uart_send(dut.clk, dut.uart_rx, m.block(add(8, OTHER, px(1500000))), DIV)
    await ClockCycles(dut.clk, ORDER)
    tail = orders[len(want):]
    assert [m.check_frame(f, V) for f in tail] == \
        ["stomped", "good" if tokens > 0 and not btn_kill else "stomped"]
