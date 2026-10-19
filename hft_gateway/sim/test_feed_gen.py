import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

import model as m
from feed_util import spi_capture


def split(frame):
    ref = int.from_bytes(frame[11:19], "big")
    ts = int.from_bytes(frame[5:11], "big")
    return (ref >> 48) & 0xFF, ref & 0xFFFFFFFF, ts


@cocotb.test()
async def stream_then_burst(dut):
    dut.go.value = 0
    dut.en.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    frames = []
    cocotb.start_soon(spi_capture(dut.clk, dut.sck, dut.mosi, dut.cs_n, frames))

    while len(frames) < 30:
        await ClockCycles(dut.clk, 100)
    await FallingEdge(dut.clk)
    dut.go.value = 1
    await FallingEdge(dut.clk)
    dut.go.value = 0
    dut.en.value = 1
    while len(frames) < 45:
        await ClockCycles(dut.clk, 100)

    kinds = []
    for i, f in enumerate(frames):
        kind, seq, ts = split(f)
        assert seq == i
        assert f == m.gen_message(seq, kind, ts), i
        kinds.append(kind)
    k = kinds.index(1)
    assert 30 <= k <= 31
    assert kinds[:k] == [0] * k
    assert kinds[k:k + 10] == list(range(1, 11))
    assert set(kinds[k + 10:]) == {0}


@cocotb.test()
async def go_during_burst_ignored(dut):
    dut.go.value = 0
    dut.en.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    frames = []
    cocotb.start_soon(spi_capture(dut.clk, dut.sck, dut.mosi, dut.cs_n, frames))
    await ClockCycles(dut.clk, 10)
    for _ in range(3):
        await FallingEdge(dut.clk)
        dut.go.value = 1
        await FallingEdge(dut.clk)
        dut.go.value = 0
        await ClockCycles(dut.clk, 3000)
    while len(frames) < 14:
        await ClockCycles(dut.clk, 100)
    kinds = [split(f)[0] for f in frames]
    assert kinds[:12] == list(range(1, 11)) + [0, 0]


@cocotb.test()
async def quiet_when_disabled(dut):
    dut.go.value = 0
    dut.en.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    frames = []
    cocotb.start_soon(spi_capture(dut.clk, dut.sck, dut.mosi, dut.cs_n, frames))
    while len(frames) < 2:
        await ClockCycles(dut.clk, 100)
    await FallingEdge(dut.clk)
    dut.en.value = 0
    dut.go.value = 1
    await FallingEdge(dut.clk)
    dut.go.value = 0
    n = len(frames)
    await ClockCycles(dut.clk, 6000)
    assert len(frames) - n <= 1
    n = len(frames)
    await ClockCycles(dut.clk, 6000)
    assert len(frames) == n
    await FallingEdge(dut.clk)
    dut.en.value = 1
    while len(frames) < n + 2:
        await ClockCycles(dut.clk, 100)
    assert all(split(f)[0] == 0 for f in frames)
