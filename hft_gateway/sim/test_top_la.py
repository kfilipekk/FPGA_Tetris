#the board at its real rates, through a simulated 24 mhz capture
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge
from cocotb.utils import get_sim_time

import capture
import model as m

PINS = ["feed_sck", "feed_mosi", "feed_cs_n", "ord_tx", "spec", "risk_ok", "tx_commit",
        "tx_abort"]
RATE = 24e6


async def record(dut, changes):
    pins = [getattr(dut, p) for p in PINS]
    last = None
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        v = sum(int(p.value) << k for k, p in enumerate(pins))
        if v != last:
            changes.append((get_sim_time("ns"), v))
            last = v


def resample(changes, t_end):
    out, j = bytearray(), 0
    for k in range(int(t_end * 1e-9 * RATE)):
        t = k / RATE * 1e9
        while j + 1 < len(changes) and changes[j + 1][0] <= t:
            j += 1
        out.append(changes[j][1])
    return out


@cocotb.test()
async def burst_capture(dut):
    dut.btn_s1.value = 1
    dut.btn_s2.value = 1
    dut.uart_rx.value = 1
    cocotb.start_soon(Clock(dut.clk, 37, "ns").start(start_high=False))
    changes = []
    cocotb.start_soon(record(dut, changes))

    await ClockCycles(dut.clk, 200000)
    dut.btn_s1.value = 0
    await ClockCycles(dut.clk, 20)
    dut.btn_s1.value = 1
    await ClockCycles(dut.clk, 11 * 140000)
    t_end = get_sim_time("ns")

    path = os.path.abspath("sim_build/top_la/burst.sr")
    capture.write_sr(path, RATE, resample(changes, t_end), PINS)
    r = capture.analyse(path)
    whys = [row["why"] for row in r["rows"]]
    lats = [row["latency"] * 1e9 for row in r["rows"]]
    dut._log.info("%d orders: %s", len(whys), whys)
    dut._log.info("sck edge to start bit %.0f to %.0f ns", min(lats), max(lats))
    assert r["problems"] == []
    burst = whys[-9:]
    assert burst[:4] == ["", "price", "fcs", "limits"]
    n = burst[4:].count("")
    assert burst[4:] == [""] * n + ["risk"] * (5 - n) and n < 5
    assert all(170 < x < 275 for x in lats)
