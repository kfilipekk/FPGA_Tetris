import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

DIV = 16  #set in cocotb.mk


async def watch(dut, out):
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.valid.value):
            out.append(int(dut.data.value))


async def line(dut, bits, div):
    for b in bits:
        dut.rx.value = b
        await ClockCycles(dut.clk, div)


@cocotb.test()
async def bytes_with_baud_error(dut):
    """3% either way still lands mid-bit"""
    dut.rx.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    got = []
    cocotb.start_soon(watch(dut, got))
    await ClockCycles(dut.clk, 5)
    random.seed(8)
    sent = []
    for _ in range(200):
        b = random.getrandbits(8)
        sent.append(b)
        div = random.choice([DIV, DIV, round(DIV * 0.97), round(DIV * 1.03)])
        await line(dut, [0] + [(b >> i) & 1 for i in range(8)] + [1], div)
        await ClockCycles(dut.clk, random.randint(0, 20))
    await ClockCycles(dut.clk, 2 * DIV)
    assert got == sent


@cocotb.test()
async def glitch_and_bad_stop_dropped(dut):
    dut.rx.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    got = []
    cocotb.start_soon(watch(dut, got))
    await ClockCycles(dut.clk, 5)
    await line(dut, [0, 1], 3)                               #too short for a start bit
    await ClockCycles(dut.clk, 2 * DIV)
    await line(dut, [0] + [1, 0] * 4 + [0], DIV)            #stop bit low
    await line(dut, [1], 3 * DIV)
    await line(dut, [0] + [1, 0, 1, 0, 0, 1, 0, 1] + [1], DIV)
    await ClockCycles(dut.clk, 2 * DIV)
    assert got == [0xA5]
