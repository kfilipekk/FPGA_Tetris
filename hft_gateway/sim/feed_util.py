#drivers and monitors for the feed side: spi pins and the byte stream behind them
from cocotb.triggers import ClockCycles


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
