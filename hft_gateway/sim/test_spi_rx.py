import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

from feed_util import spi_send


async def watch(dut, out):
    """frames as lists of (byte, sof), closed on eof"""
    cur = []
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.valid.value):
            cur.append((int(dut.data.value), int(dut.sof.value)))
        if int(dut.eof.value):
            out.append(cur)
            cur = []


@cocotb.test()
async def frames_at_any_rate(dut):
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.sck.value = 0
    dut.mosi.value = 0
    dut.cs_n.value = 1
    await ClockCycles(dut.clk, 5)
    got = []
    cocotb.start_soon(watch(dut, got))

    random.seed(2)
    sent = []
    for _ in range(20):
        data = bytes(random.getrandbits(8) for _ in range(random.randint(1, 45)))
        sent.append(data)
        await spi_send(dut.clk, dut.sck, dut.mosi, dut.cs_n, data, half=random.randint(2, 9))
        await ClockCycles(dut.clk, random.randint(1, 10))
    await ClockCycles(dut.clk, 10)

    assert len(got) == len(sent)
    for data, frame in zip(sent, got):
        assert bytes(b for b, _ in frame) == data
        assert [s for _, s in frame] == [1] + [0] * (len(data) - 1)


@cocotb.test()
async def partial_byte_dropped(dut):
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.sck.value = 0
    dut.mosi.value = 0
    dut.cs_n.value = 1
    await ClockCycles(dut.clk, 5)
    got = []
    cocotb.start_soon(watch(dut, got))

    #five clocks then cs up, then a clean frame
    dut.cs_n.value = 0
    for _ in range(5):
        dut.mosi.value = 1
        await ClockCycles(dut.clk, 4)
        dut.sck.value = 1
        await ClockCycles(dut.clk, 4)
        dut.sck.value = 0
    await ClockCycles(dut.clk, 4)
    dut.cs_n.value = 1
    await ClockCycles(dut.clk, 10)
    await spi_send(dut.clk, dut.sck, dut.mosi, dut.cs_n, b"\xA5\x0F", half=4)
    await ClockCycles(dut.clk, 10)

    assert got == [[], [(0xA5, 1), (0x0F, 0)]]
