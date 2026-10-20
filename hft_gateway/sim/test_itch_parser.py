import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import model as m

V = os.environ.get("VENUE", "nasdaq")
N = m.VENUES[V]["feed"]
TRIG, PX = (23, 33) if V == "lse" else (32, 36)
PRICE = m.VENUES[V]["limit"] - 1000 * m.VENUES[V]["scale"]


def add(ref, shares, price):
    if V == "lse":
        return m.mitch_add(ref, b"S", shares, 1001, price)
    return m.itch_add(ref, b"S", shares, m.SYMBOL, price)


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
    if not m.triggers(msg, venue=V):
        return []
    p = m.parse_feed(msg, V)
    ev = [("trig", p["ref"], p["shares"])]
    if len(msg) >= PX:
        ev.append(("px", p["price"]))
    ev.append(("done", int(len(msg) >= N + 4 and p["fcs_ok"])))
    return ev


def frames(n):
    random.seed(3)
    out = []
    for s in range(n):
        msg = m.gen_message(s, 0, ts=random.getrandbits(48), venue=V)
        r = random.random()
        if r < 0.1:
            msg = msg[:random.randint(1, N + 3)]         #cut short
        elif r < 0.15:
            msg = msg + bytes(random.randint(1, 5))      #trailing bytes, ignored
        elif r < 0.2:
            i = random.randrange(N + 4)                  #one flipped bit
            msg = msg[:i] + bytes([msg[i] ^ (1 << random.randrange(8))]) + msg[i + 1:]
        elif r < 0.25:
            t = 1 if V == "lse" else 0                   #not an add order
            msg = msg[:t] + b"E" + msg[t + 1:]
        out.append(msg)
    for k in (1, 2, 3, 4, 6):
        out.append(m.gen_message(k, k, venue=V))
    return out


@cocotb.test()
async def against_model(dut):
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.valid.value = 0
    dut.data.value = 0
    dut.sof.value = 0
    dut.eof.value = 0
    dut.symbol.value = int.from_bytes(m.VENUES[V]["symbol"], "big")
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
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.valid.value = 0
    dut.data.value = 0
    dut.sof.value = 0
    dut.eof.value = 0
    dut.symbol.value = int.from_bytes(m.VENUES[V]["symbol"], "big")
    await ClockCycles(dut.clk, 3)
    ev = []
    cocotb.start_soon(watch(dut, ev))

    good = add(7, 300, PRICE)
    await send(dut, good, (0, 0))
    assert ev == [("trig", 7, 300), ("px", PRICE), ("done", 1)]

    ev.clear()
    cut = TRIG + 2
    for i, b in enumerate(good[:cut] + good):
        await FallingEdge(dut.clk)
        dut.valid.value = 1
        dut.data.value = b
        dut.sof.value = int(i in (0, cut))
    await FallingEdge(dut.clk)
    dut.valid.value = 0
    dut.sof.value = 0
    await ClockCycles(dut.clk, 3)
    assert ev == [("trig", 7, 300), ("done", 0), ("trig", 7, 300), ("px", PRICE), ("done", 1)]
