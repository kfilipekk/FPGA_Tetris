#drivers and monitors for the feed side: spi pins and the byte stream behind them
import random

from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly


async def spi_send(clk, sck, mosi, cs_n, data, half=4):
    """one cs frame, mode 0, msb first"""
    cs_n.value = 0
    await ClockCycles(clk, half)
    for b in data:
        for i in range(7, -1, -1):
            mosi.value = (b >> i) & 1
            await ClockCycles(clk, half)
            sck.value = 1
            await ClockCycles(clk, half)
            sck.value = 0
    await ClockCycles(clk, half)
    cs_n.value = 1
    await ClockCycles(clk, half)


async def stream_send(dut, data, gaps=(0, 0)):
    """bytes on in_valid/in_data with sof on the first and eof after, from a falling edge"""
    for i, b in enumerate(data):
        await FallingEdge(dut.clk)
        dut.in_valid.value = 1
        dut.in_data.value = b
        dut.in_sof.value = int(i == 0)
        await FallingEdge(dut.clk)
        dut.in_valid.value = 0
        dut.in_sof.value = 0
        g = random.randint(*gaps)
        if g:
            await ClockCycles(dut.clk, g, rising=False)
    await FallingEdge(dut.clk)
    dut.in_eof.value = 1
    await FallingEdge(dut.clk)
    dut.in_eof.value = 0


async def byte_capture(clk, valid, ready, data, frames, flen):
    """bytes taken on valid and ready, cut into frames of flen. looks mid-cycle, after
    the testbench has set ready for the coming edge"""
    cur = bytearray()
    while True:
        await FallingEdge(clk)
        await ReadOnly()
        if int(valid.value) and int(ready.value):
            cur.append(int(data.value))
            if len(cur) == flen:
                frames.append(bytes(cur))
                cur = bytearray()
