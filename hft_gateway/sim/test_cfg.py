import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

import model as m


async def send(dut, data):
    for i, b in enumerate(data):
        await FallingEdge(dut.clk)
        dut.valid.value = 1
        dut.data.value = b
        dut.sof.value = int(i == 0)
        await FallingEdge(dut.clk)
        dut.valid.value = 0
        dut.sof.value = 0
    await FallingEdge(dut.clk)
    dut.eof.value = 1
    await FallingEdge(dut.clk)
    dut.eof.value = 0
    await ClockCycles(dut.clk, 2)


def state(dut):
    return (int(dut.symbol.value).to_bytes(8, "big"), int(dut.limit.value), int(dut.kill.value))


@cocotb.test()
async def only_clean_frames_apply(dut):
    for s in (dut.valid, dut.data, dut.sof, dut.eof):
        s.value = 0
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    await ClockCycles(dut.clk, 3)
    assert state(dut) == (m.SYMBOL, m.LIMIT, 0)

    good = m.config(m.symbol_of("NVDA"), 1420000, kill=True)
    await send(dut, good[:-1] + bytes([good[-1] ^ 1]))       #bad fcs
    await send(dut, good + b"\x00")                          #too long
    await send(dut, good[:17])                               #too short
    await send(dut, b"D" + good[1:])                         #not a config frame
    await send(dut, m.itch_add(1, b"S", 100, m.SYMBOL, 1))   #a message
    assert state(dut) == (m.SYMBOL, m.LIMIT, 0)

    await send(dut, good)
    assert state(dut) == (m.symbol_of("NVDA"), 1420000, 1)
    await send(dut, m.config(m.SYMBOL, m.LIMIT, kill=False))
    assert state(dut) == (m.SYMBOL, m.LIMIT, 0)
