import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import model as m


async def watch(dut, ev):
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.trig.value):
            ev.append(("trig", int(dut.ref_num.value), int(dut.shares.value)))
        if int(dut.px_valid.value):
            ev.append(("px", int(dut.price.value)))
        if int(dut.done.value):
            ev.append(("done", int(dut.ok.value)))


async def send(dut, data, gaps):
    for i, b in enumerate(data):
        await FallingEdge(dut.clk)
        dut.valid.value = 1
        dut.data.value = b
        dut.sof.value = int(i == 0)
        await FallingEdge(dut.clk)
        dut.valid.value = 0
        dut.sof.value = 0
        g = random.randint(*gaps)
        if g:
            await ClockCycles(dut.clk, g, rising=False)
    await FallingEdge(dut.clk)
    dut.eof.value = 1
    await FallingEdge(dut.clk)
    dut.eof.value = 0
    await ClockCycles(dut.clk, 3)


def expect(msg):
    if not m.triggers(msg):
        return []
    p = m.parse_itch(msg)
    ev = [("trig", p["ref"], p["shares"])]
    if len(msg) >= 36:
        ev.append(("px", p["price"]))
    ev.append(("done", int(len(msg) >= 40 and p["fcs_ok"])))
    return ev


def frames(n):
    random.seed(3)
    out = []
    for s in range(n):
        msg = m.gen_message(s, 0, ts=random.getrandbits(48))
        r = random.random()
        if r < 0.1:
            msg = msg[:random.randint(1, 39)]            #cut short
        elif r < 0.15:
            msg = msg + bytes(random.randint(1, 5))      #trailing bytes, ignored
        elif r < 0.2:
            i = random.randrange(40)                     #one flipped bit
            msg = msg[:i] + bytes([msg[i] ^ (1 << random.randrange(8))]) + msg[i + 1:]
        elif r < 0.25:
            msg = b"E" + msg[1:]                         #not an add order
        out.append(msg)
    #always a few of ours
    for k in (1, 2, 3, 4, 6):
        out.append(m.gen_message(k, k))
    return out


@cocotb.test()
async def against_model(dut):
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.valid.value = 0
    dut.data.value = 0
    dut.sof.value = 0
    dut.eof.value = 0
    await ClockCycles(dut.clk, 3)
    ev = []
    cocotb.start_soon(watch(dut, ev))

    hits = 0
    for msg in frames(400):
        ev.clear()
        await send(dut, msg, (0, 2))
        assert ev == expect(msg), msg.hex()
        hits += bool(ev)
    assert hits > 40


@cocotb.test()
async def back_to_back(dut):
    """no idle clocks between bytes, and a new frame cutting off one in flight"""
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.valid.value = 0
    dut.data.value = 0
    dut.sof.value = 0
    dut.eof.value = 0
    await ClockCycles(dut.clk, 3)
    ev = []
    cocotb.start_soon(watch(dut, ev))

    good = m.itch_add(7, b"S", 300, b"AAPL    ", 1499000)
    await send(dut, good, (0, 0))
    assert ev == [("trig", 7, 300), ("px", 1499000), ("done", 1)]

    #sof with no eof between: the cut one fails
    ev.clear()
    for i, b in enumerate(good[:34] + good):
        await FallingEdge(dut.clk)
        dut.valid.value = 1
        dut.data.value = b
        dut.sof.value = int(i in (0, 34))
    await FallingEdge(dut.clk)
    dut.valid.value = 0
    dut.sof.value = 0
    await ClockCycles(dut.clk, 3)
    assert ev == [("trig", 7, 300), ("done", 0), ("trig", 7, 300), ("px", 1499000), ("done", 1)]
