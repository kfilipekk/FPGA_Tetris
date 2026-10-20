import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly

import model as m

VENUE = os.environ.get("VENUE", "nasdaq")
LEN = m.VENUES[VENUE]["order"]
PXI, PXN = (67, 8) if VENUE == "lse" else (28, 4)
STOCK = m.VENUES[VENUE]["symbol"]


def expected(token, qty, stock, price, px_fire, dec, fires):
    payload = bytearray(m.order_payload(token, qty, stock, price, VENUE))
    have_px = lambda c: px_fire is not None and px_fire < c
    for k in range(PXI, PXI + PXN):
        if not have_px(fires[k]):
            payload[k] = 0
    poison = not have_px(fires[PXI])
    good = False
    if dec is not None:
        c, commit = dec
        #counts before the first fcs byte's clock, or on it if that byte waits
        if c < fires[LEN]:
            good = commit
    if poison:
        good = False
    return m.frame_of(bytes(payload), good), good


async def run(dut, token, qty, stock, price, px_at, dec_at, commit, p_ready):
    await FallingEdge(dut.clk)
    dut.start.value = 1
    dut.token.value = token
    dut.qty.value = qty
    dut.stock.value = int.from_bytes(stock, "big")
    await FallingEdge(dut.clk)
    dut.start.value = 0

    out, fires, cyc, px_fire, dec = bytearray(), [], 0, None, None
    while True:
        dut.px_valid.value = int(cyc == px_at)
        dut.price.value = price if cyc == px_at else random.getrandbits(63)
        dut.decide.value = int(cyc == dec_at)
        dut.commit.value = commit if cyc == dec_at else random.getrandbits(1)
        dut.ready.value = int(random.random() < p_ready)
        await ReadOnly()
        if not int(dut.busy.value):
            break
        if cyc == px_at:
            px_fire = cyc
        if cyc == dec_at:
            dec = (cyc, commit)
        if int(dut.valid.value) and int(dut.ready.value):
            out.append(int(dut.data.value))
            fires.append(cyc)
        await FallingEdge(dut.clk)
        cyc += 1
    return bytes(out), fires, px_fire, dec


async def setup(dut):
    for s in (dut.start, dut.px_valid, dut.decide, dut.commit, dut.ready, dut.token,
              dut.qty, dut.stock, dut.price):
        s.value = 0
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await ClockCycles(dut.clk, 3)


@cocotb.test()
async def random_timing(dut):
    await setup(dut)
    random.seed(5)
    n_good = n_stomp = 0
    for i in range(300):
        token = random.getrandbits(56)
        qty = random.randint(1, 1000)
        price = random.getrandbits(32 if VENUE == "nasdaq" else 63)
        p_ready = random.choice([1.0, 0.5, 0.2])
        span = int((LEN + 11) / p_ready)
        #mostly in time, some late, some never
        px_at = random.choice([random.randint(0, 20)] * 3 + [random.randint(0, span), None])
        dec_at = random.choice([random.randint(0, 40)] * 3 + [random.randint(0, span), None])
        commit = random.getrandbits(1)
        out, fires, px_fire, dec = await run(dut, token, qty, STOCK, price,
                                             px_at, dec_at, commit, p_ready)
        want, good = expected(token, qty, STOCK, price, px_fire, dec, fires)
        assert out == want, (i, px_at, dec_at, commit)
        assert m.check_frame(out, VENUE) == ("good" if good else "stomped")
        n_good += good
        n_stomp += not good
    assert n_good > 30 and n_stomp > 30


@cocotb.test()
async def early_verdict(dut):
    await setup(dut)
    px = m.VENUES[VENUE]["limit"] - 1
    out, fires, px_fire, dec = await run(dut, 0x0100000000002A, 100, STOCK, px, 2, 4, 1, 1.0)
    assert out == m.frame_of(m.order_payload(0x0100000000002A, 100, STOCK, px, VENUE), True)
    assert fires == list(range(LEN + 4))


@cocotb.test()
async def late_verdict(dut):
    await setup(dut)
    out, *_ = await run(dut, 1, 100, STOCK, 1499000, 2, LEN + 1, 1, 1.0)
    assert m.check_frame(out, VENUE) == "stomped"
    await ClockCycles(dut.clk, 2)
