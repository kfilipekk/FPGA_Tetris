#the whole board: the on-chip feed, through the spi pins, out of the uart
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import model as m
from feed_util import spi_capture
from uart_util import recv_byte

DIV = 8      #set in cocotb.mk
HOLD = 4
BURST = 4


async def uart_frames(dut, out):
    cur = bytearray()
    while True:
        cur.append(await recv_byte(dut.clk, dut.uart_tx, DIV))
        if len(cur) == m.FRAME_LEN:
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
        v = m.verdict(f, tokens=tokens, kill=kill)
        if v is not None:
            tokens -= v[1] == ""
            out.append((m.frame_of(v[0], v[1] == ""), v[1]))
    return out, tokens


@cocotb.test()
async def burst_then_kill(dut):
    dut.btn_s1.value = 1
    dut.btn_s2.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
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

    #the first streamed message and its order, then the scripted burst
    while len(feed) < 1:
        await ClockCycles(dut.clk, 100)
    await ClockCycles(dut.clk, 6000)
    await press(dut, dut.btn_s1)
    while len(feed) < 11:
        await ClockCycles(dut.clk, 1000)
    await ClockCycles(dut.clk, 6000)

    kinds = [(int.from_bytes(f[11:19], "big") >> 48) & 0xFF for f in feed]
    assert kinds == [0] + list(range(1, 11))
    want, tokens = expected(feed, BURST)
    assert orders == [w for w, _ in want]
    #every path, then commits until the bucket runs dry (the streamed one may have
    #taken a token)
    whys = [w for _, w in want][-9:]
    assert whys[:4] == ["", "price", "fcs", "limits"]
    n = whys[4:].count("")
    assert whys[4:] == [""] * n + ["tokens"] * (5 - n) and n < 5
    assert seen == {"spec", "tx_commit", "tx_abort"}
    await ReadOnly()
    assert int(dut.risk_ok.value) == int(tokens > 0)

    #kill on: every order goes out stomped
    await FallingEdge(dut.clk)
    await press(dut, dut.btn_s2)
    await ReadOnly()
    assert int(dut.risk_ok.value) == 0
    await FallingEdge(dut.clk)
    n_feed, n_orders = len(feed), len(orders)
    await press(dut, dut.btn_s1)
    while len(feed) < n_feed + 10:
        await ClockCycles(dut.clk, 1000)
    await ClockCycles(dut.clk, 6000)
    want, _ = expected(feed[n_feed:], tokens, kill=True)
    assert orders[n_orders:] == [w for w, _ in want]
    assert all(m.check_frame(f) == "stomped" for f in orders[n_orders:])


@cocotb.test()
async def pin_latency(dut):
    """from the sck edge that samples the symbol's last bit to the order's start bit"""
    dut.btn_s1.value = 1
    dut.btn_s2.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await ClockCycles(dut.clk, 2)
    await press(dut, dut.btn_s2)    #kill off again, it carried over
    await FallingEdge(dut.clk)
    await press(dut, dut.btn_s1)
    #count from a cs fall, in case a frame was already going
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
        if synced and tx == 0 and last_tx == 1 and len(edges) >= 32 * 8:
            start = cyc
        last_sck, last_cs, last_tx = s, c, tx
    lat = start - edges[32 * 8 - 1]
    dut._log.info("sck edge to start bit: %d clocks, %.0f ns at 27 MHz", lat, lat * 1e9 / 27e6)
    #3 to sync and find the edge, then the byte, the trigger, the launch, the uart
    assert lat == 6
