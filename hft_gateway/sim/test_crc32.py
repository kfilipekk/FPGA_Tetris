import random
import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge


@cocotb.test()
async def matches_zlib(dut):
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    dut.init.value = 0
    dut.en.value = 0
    dut.d.value = 0
    random.seed(1)
    for n in [1, 2, 36, 49, 100] + [random.randint(1, 64) for _ in range(30)]:
        data = bytes(random.getrandbits(8) for _ in range(n))
        for i, b in enumerate(data):
            await FallingEdge(dut.clk)
            dut.init.value = int(i == 0)
            dut.en.value = 1
            dut.d.value = b
            if random.random() < 0.3:
                await FallingEdge(dut.clk)
                dut.init.value = 0
                dut.en.value = 0
        await FallingEdge(dut.clk)
        dut.init.value = 0
        dut.en.value = 0
        await FallingEdge(dut.clk)
        assert int(dut.c.value) ^ 0xFFFFFFFF == zlib.crc32(data), n


@cocotb.test()
async def init_alone_clears(dut):
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await FallingEdge(dut.clk)
    dut.init.value = 0
    dut.en.value = 1
    dut.d.value = 0x5A
    await FallingEdge(dut.clk)
    dut.en.value = 0
    dut.init.value = 1
    await FallingEdge(dut.clk)
    dut.init.value = 0
    assert int(dut.c.value) == 0xFFFFFFFF
    await ClockCycles(dut.clk, 2)
