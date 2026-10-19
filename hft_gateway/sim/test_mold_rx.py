import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

IDLE = 50  #set in cocotb.mk


async def watch(dut, out):
    cur = []
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.valid.value):
            assert not int(dut.eof.value)
            cur.append((int(dut.data.value), int(dut.sof.value)))
        if int(dut.eof.value):
            out.append(cur)
            cur = []


async def send(dut, data, gap=(1, 4)):
    for b in data:
        await FallingEdge(dut.clk)
        dut.in_valid.value = 1
        dut.in_data.value = b
        await FallingEdge(dut.clk)
        dut.in_valid.value = 0
        await ClockCycles(dut.clk, random.randint(*gap), rising=False)


async def setup(dut):
    dut.in_valid.value = 0
    dut.in_data.value = 0
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    got = []
    cocotb.start_soon(watch(dut, got))
    await ClockCycles(dut.clk, 3)
    return got


@cocotb.test()
async def blocks(dut):
    got = await setup(dut)
    random.seed(9)
    sent = []
    for _ in range(50):
        msg = bytes(random.getrandbits(8) for _ in range(random.randint(1, 60)))
        sent.append(msg)
        await send(dut, len(msg).to_bytes(2, "big") + msg)
    await send(dut, b"\x00\x00")
    await send(dut, b"\x00\x01\x7f")
    await ClockCycles(dut.clk, 10)
    sent.append(b"\x7f")
    assert [bytes(b for b, _ in f) for f in got] == sent
    assert all([s for _, s in f] == [1] + [0] * (len(f) - 1) for f in got)


@cocotb.test()
async def lost_byte_costs_one_block(dut):
    got = await setup(dut)
    await send(dut, b"\x00\x05abcd")             #one short
    await ClockCycles(dut.clk, IDLE + 10)
    await send(dut, b"\x00\x03xyz")
    await send(dut, b"\x00")                     #half a length
    await ClockCycles(dut.clk, IDLE + 10)
    await send(dut, b"\x00\x02ok")
    await ClockCycles(dut.clk, 10)
    assert [bytes(b for b, _ in f) for f in got] == [b"abcd", b"xyz", b"ok"]
