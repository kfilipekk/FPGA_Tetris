#the replay's file reading and checking, on a made up itch day, run with plain python
import gzip
import io
import os
import struct
import tempfile

import itch_cut
import model as m
import replay as r


def day():
    """a few message types as nasdaq writes them, adds for two stocks among them"""
    out = []
    for i in range(300):
        stock = b"AAPL    " if i % 3 == 0 else b"MSFT    "
        out.append(m.itch_add(i, b"S" if i % 2 else b"B", 100, stock, 1500000 + i)[:36])
        if i % 10 == 0:
            out.append(b"S" + bytes(11))                      #system event
            out.append(b"E" + bytes(30))                      #order executed
    return b"".join(struct.pack(">H", len(x)) + x for x in out)


def test_read_itch_adds_only():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "day.itch.gz")
        with gzip.open(p, "wb") as f:
            f.write(day())
        msgs = list(r.read_itch(p))
        assert len(msgs) == 300 and all(len(x) == 40 and x[0:1] == b"A" for x in msgs)
        assert all(m.parse_itch(x)["fcs_ok"] for x in msgs)
        aapl = list(r.read_itch(p, b"AAPL    ", count=20))
        assert len(aapl) == 20 and all(x[24:32] == b"AAPL    " for x in aapl)


def test_cut():
    out = io.BytesIO()
    kept, others = itch_cut.cut(io.BytesIO(day()), out, b"AAPL    ", 50, every=10)
    assert kept == 50
    raw = out.getvalue()
    n, msgs = 0, []
    while n < len(raw):
        ln = struct.unpack(">H", raw[n:n + 2])[0]
        msgs.append(raw[n + 2:n + 2 + ln])
        n += 2 + ln
    assert sum(x[24:32] == b"AAPL    " for x in msgs) == 50
    assert sum(x[24:32] == b"MSFT    " for x in msgs) == others // 10


def test_check():
    sym, lim = m.SYMBOL, m.LIMIT
    good = m.itch_add(1, b"S", 100, sym, lim - 1)
    over = m.itch_add(2, b"S", 100, sym, lim + 1)
    buy = m.itch_add(3, b"B", 100, sym, lim - 1)
    pg = m.verdict(good)[0]
    po = m.verdict(over)[0]
    assert r.check(good, (m.frame_of(pg, True), "good"), sym, lim) == ("commit", None)
    assert r.check(good, (m.frame_of(pg, False), "stomped"), sym, lim) == ("risk", None)
    assert r.check(over, (m.frame_of(po, False), "stomped"), sym, lim) == ("price", None)
    assert r.check(over, (m.frame_of(po, True), "good"), sym, lim)[1]
    assert r.check(good, None, sym, lim)[1]
    assert r.check(buy, None, sym, lim) == ("none", None)
    assert r.check(buy, (m.frame_of(pg, True), "good"), sym, lim)[1]
    assert r.check(good, (m.frame_of(po, False), "stomped"), sym, lim)[1]


if __name__ == "__main__":
    for name, f in list(globals().items()):
        if name.startswith("test_"):
            f()
    print("ok")
