import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import model as m
from feed_util import byte_capture, stream_send


async def ready_gen(dut, p):
    while True:
        await FallingEdge(dut.clk)
        dut.out_ready.value = int(random.random() < p[0])


async def setup(dut, p_ready=1.0):
    for s in (dut.in_valid, dut.in_data, dut.in_sof, dut.in_eof, dut.kill, dut.out_ready):
        s.value = 0
    dut.symbol.value = int.from_bytes(m.SYMBOL, "big")
    dut.limit.value = m.LIMIT
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    p = [p_ready]
    cocotb.start_soon(ready_gen(dut, p))
    frames = []
    cocotb.start_soon(byte_capture(dut.clk, dut.out_valid, dut.out_ready, dut.out_data,
                                   frames, m.FRAME_LEN))
    await ClockCycles(dut.clk, 3)
    return frames, p


async def drain(dut):
    await ClockCycles(dut.clk, 2)
    while int(dut.out_valid.value):
        await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, 2)


def mixed(n, seed):
    random.seed(seed)
    out = []
    for s in range(n):
        msg = m.gen_message(s, 0, ts=random.getrandbits(48))
        r = random.random()
        if r < 0.08:
            msg = msg[:random.randint(1, 39)]
        elif r < 0.14:
            i = random.randrange(40)
            msg = msg[:i] + bytes([msg[i] ^ (1 << random.randrange(8))]) + msg[i + 1:]
        elif r < 0.4:
            #ours, near the limit
            msg = m.itch_add(random.getrandbits(64), b"S", random.randint(1, 400), m.SYMBOL,
                             m.LIMIT + random.randint(-3, 3), bad=random.random() < 0.1)
        out.append(msg)
    return out


@cocotb.test()
async def against_model(dut):
    frames, p = await setup(dut)
    want = []
    whys = set()
    for i, msg in enumerate(mixed(300, 6)):
        p[0] = random.choice([1.0, 0.7, 0.3])
        await stream_send(dut, msg, (0, 2))
        await drain(dut)
        v = m.verdict(msg)
        if v is not None:
            want.append(m.frame_of(v[0], v[1] == ""))
            whys.add(v[1])
        assert frames == want, i
    assert whys == {"", "price", "fcs", "limits"}


@cocotb.test()
async def kill_stomps(dut):
    frames, _ = await setup(dut)
    msg = m.itch_add(1, b"S", 100, m.SYMBOL, 1499000)
    await stream_send(dut, msg)
    await drain(dut)
    await FallingEdge(dut.clk)
    dut.kill.value = 1
    await stream_send(dut, msg)
    await drain(dut)
    assert [m.check_frame(f) for f in frames] == ["good", "stomped"]


@cocotb.test()
async def price_too_late(dut):
    """a clean order on a feed slower than the order port: the price misses its field"""
    frames, _ = await setup(dut)
    msg = m.itch_add(2, b"S", 100, m.SYMBOL, 1499000)
    await stream_send(dut, msg, (12, 12))
    await drain(dut)
    assert len(frames) == 1
    assert m.check_frame(frames[0]) == "stomped"
    assert frames[0][28:32] == bytes(4)


@cocotb.test()
async def busy_misses(dut):
    """a second match while the first order is still going gets no order"""
    frames, p = await setup(dut, 0.05)
    missed = []

    async def watch():
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            if int(dut.missed.value):
                missed.append(1)
    cocotb.start_soon(watch())

    a = m.itch_add(3, b"S", 100, m.SYMBOL, 1499000)
    b = m.itch_add(4, b"S", 100, m.SYMBOL, 1499000)
    await stream_send(dut, a)
    await stream_send(dut, b)
    p[0] = 1.0
    await drain(dut)
    assert frames == [m.frame_of(m.verdict(a)[0], True)]
    assert missed == [1]


@cocotb.test()
async def latency(dut):
    """clocks from the symbol's last byte to the first order byte, and from the last
    fcs byte to the commit"""
    frames, _ = await setup(dut)
    msg = m.itch_add(5, b"S", 100, m.SYMBOL, 1499000)
    t = {}

    async def watch():
        cyc, n = 0, 0
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            cyc += 1
            if int(dut.in_valid.value):
                n += 1
                if n == 32:
                    t["sym"] = cyc
                if n == 40:
                    t["fcs"] = cyc
            if int(dut.out_valid.value) and "out" not in t:
                t["out"] = cyc
            if int(dut.tx_commit.value) and "commit" not in t:
                t["commit"] = cyc
    cocotb.start_soon(watch())
    await stream_send(dut, msg)
    await drain(dut)
    assert m.check_frame(frames[0]) == "good"
    #inputs change on the falling edge, so they are seen one sample after the clock
    #they are presented in. outputs are seen in the clock they are presented in
    tick_to_order = t["out"] - t["sym"] + 1
    verdict = t["commit"] - t["fcs"] + 1
    dut._log.info("first order byte %d clocks after the symbol, commit %d after the fcs",
                  tick_to_order, verdict)
    assert tick_to_order == 2
    assert verdict == 3


@cocotb.test()
async def settings_held_from_launch(dut):
    """a new symbol and limit take effect on the next order, not the one going"""
    frames, _ = await setup(dut)
    msft = m.symbol_of("MSFT")
    a = m.itch_add(10, b"S", 100, msft, 1550000)
    await stream_send(dut, a)
    await drain(dut)
    assert frames == []                         #not our symbol yet
    await FallingEdge(dut.clk)
    dut.symbol.value = int.from_bytes(msft, "big")
    await stream_send(dut, a)
    await drain(dut)                            #over $150
    await FallingEdge(dut.clk)
    dut.limit.value = 1600000
    await stream_send(dut, a)
    await drain(dut)                            #under $160
    #the limit drops once the order is going: it keeps the one it launched with
    b = m.itch_add(11, b"S", 100, msft, 1550000)
    cocotb.start_soon(stream_send(dut, b))
    while not int(dut.out_valid.value):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.limit.value = 1000000
    await drain(dut)
    await ClockCycles(dut.clk, 20)
    assert [m.check_frame(f) for f in frames] == ["stomped", "good", "good"]
    assert frames[1] == m.frame_of(m.verdict(a, symbol=msft, limit=1600000)[0], True)
