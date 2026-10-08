import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import model as m

BURST, REFILL = 3, 40  #set in cocotb.mk


def limits(price, qty):
    return m.risk_limits(price, qty)


async def idle(dut):
    dut.kill.value = 0
    dut.check.value = 0
    dut.price.value = 1500000
    dut.qty.value = 100


async def sync_tick(dut):
    """drain the bucket and wait for a token back, after which the refill counter is 0"""
    while int(dut.tokens.value):
        await FallingEdge(dut.clk)
        dut.check.value = 1
        await FallingEdge(dut.clk)
        dut.check.value = 0
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.tokens.value):
            break
    await FallingEdge(dut.clk)


@cocotb.test()
async def against_model(dut):
    await idle(dut)
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await ClockCycles(dut.clk, 2)
    await sync_tick(dut)

    tokens, tick = 1, 0   #the clock after a refill
    random.seed(4)
    grants = 0
    for cyc in range(4000):
        kill = random.random() < 0.05
        check = random.random() < 0.15
        price = random.choice([1499000, 1500000, 999999, 1000000, 2000000, 2000001, 100])
        qty = random.choice([0, 1, 100, 333, 334, 500, 501])
        dut.kill.value = kill
        dut.check.value = check
        dut.price.value = price
        dut.qty.value = qty
        await ReadOnly()
        assert int(dut.armed.value) == int(not kill and tokens > 0), cyc

        refill = tick == REFILL - 1
        ok = check and not kill and tokens > 0 and limits(price, qty)
        tokens = min(BURST, tokens - ok + refill)
        tick = 0 if refill else tick + 1

        await RisingEdge(dut.clk)
        await ReadOnly()
        assert int(dut.grant.value) == int(ok), cyc
        assert int(dut.deny.value) == int(check and not ok), cyc
        assert int(dut.tokens.value) == tokens, cyc
        grants += ok
        await FallingEdge(dut.clk)
    assert grants > 50


@cocotb.test()
async def rate_bounded(dut):
    """checks every clock: never more than BURST + 1 grants in a REFILL window"""
    await idle(dut)
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await ClockCycles(dut.clk, 2)
    hist = []
    for _ in range(20 * REFILL):
        await FallingEdge(dut.clk)
        dut.check.value = 1
        await RisingEdge(dut.clk)
        await ReadOnly()
        hist.append(int(dut.grant.value))
        assert sum(hist[-REFILL:]) <= BURST + 1
    #and the long run rate is one per REFILL
    assert abs(sum(hist[-10 * REFILL:]) - 10) <= 1


@cocotb.test()
async def kill_blocks_everything(dut):
    await idle(dut)
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await FallingEdge(dut.clk)
    dut.kill.value = 1
    for _ in range(200):
        dut.check.value = 1
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert int(dut.grant.value) == 0
        assert int(dut.armed.value) == 0
        await FallingEdge(dut.clk)
    dut.check.value = 0
    await ClockCycles(dut.clk, 2)
