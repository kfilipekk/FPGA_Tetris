#bucket of three, no refill
import cocotb
from cocotb.triggers import ReadOnly

import model as m
from feed_util import stream_send
from test_hft_core import drain, setup

BURST = 3


@cocotb.test()
async def bucket_runs_dry(dut):
    frames, _ = await setup(dut)
    want, armed = [], []
    tokens = BURST
    for i in range(6):
        price = 1501000 if i == 1 else 1499000
        msg = m.itch_add(i, b"S", 100, m.SYMBOL, price)
        await stream_send(dut, msg)
        await drain(dut)
        payload, why = m.verdict(msg, tokens=tokens)
        tokens -= why == ""
        want.append(m.frame_of(payload, why == ""))
        await ReadOnly()
        armed.append(int(dut.armed.value))
    assert frames == want
    assert [m.check_frame(f) for f in frames] == \
        ["good", "stomped", "good", "good", "stomped", "stomped"]
    assert armed == [1, 1, 1, 0, 0, 0]
