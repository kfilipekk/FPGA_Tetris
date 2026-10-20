import os
import tempfile

import capture as c
import model as m

RATE = 24e6
BAUD = 115200


class Line:
    def __init__(self):
        self.s = bytearray()
        self.v = 0b0000_1100

    def set(self, ch, b):
        self.v = (self.v & ~(1 << ch)) | (b << ch)

    def hold(self, n):
        self.s += bytes([self.v]) * int(n)


def build(msg, order, good, gap_samples=6):
    L = Line()
    L.hold(50)
    L.set(c.CH["cs_n"], 0)
    L.hold(12)
    edge256 = None
    for k, b in enumerate(msg):
        for i in range(7, -1, -1):
            L.set(c.CH["mosi"], (b >> i) & 1)
            L.hold(14)
            L.set(c.CH["sck"], 1)
            if k * 8 + 7 - i == 255:
                edge256 = len(L.s)
                L.hold(gap_samples)
                L.set(c.CH["spec"], 1)
                start = len(L.s)
                break
            L.hold(14)
            L.set(c.CH["sck"], 0)
        if edge256 is not None:
            break
    feed_bits = []
    for b in msg[32:]:
        feed_bits += [(b >> i) & 1 for i in range(7, -1, -1)]
    uart = []
    for b in order:
        uart += [0] + [(b >> i) & 1 for i in range(8)] + [1]
    spb = RATE / BAUD
    total = int(len(uart) * spb) + 10
    feed_len = 28 - gap_samples + len(feed_bits) * 28
    for n in range(total):
        t = n + gap_samples
        L.set(c.CH["ord_tx"], uart[min(int(n / spb), len(uart) - 1)])
        if t < 14:
            pass
        elif t - 14 < feed_len - 28 + 14:
            j = (t - 14) // 28 + 0
            if j < len(feed_bits):
                ph = (t - 14) % 28
                L.set(c.CH["sck"], int(ph >= 14))
                L.set(c.CH["mosi"], feed_bits[j])
        else:
            L.set(c.CH["sck"], 0)
            L.set(c.CH["cs_n"], 1)
            L.set(c.CH["spec"], 0)
            L.set(c.CH["commit" if good else "abort"], 1)
        L.hold(1)
    L.set(c.CH["commit"], 0)
    L.set(c.CH["abort"], 0)
    L.hold(500)
    return bytes(L.s), edge256, start


def test_round_trip():
    msg = m.itch_add(42, b"S", 100, m.SYMBOL, 1499000)
    payload, why = m.verdict(msg)
    order = m.frame_of(payload, True)
    s, e, st = build(msg, order, True)
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "x.sr")
        c.write_sr(p, RATE, s)
        rate, back = c.read_sr(p)
        assert rate == RATE and back == s
        feed = c.spi_frames(back)
        assert feed[0][0] == msg
        assert feed[0][1][255] == e
        r = c.analyse(p)
    assert r["problems"] == []
    row, = r["rows"]
    assert row["status"] == "good" and row["line"] == "commit" and row["seq"] == 42
    assert abs(row["latency"] - 6 / RATE) < 1e-9


def test_catches_wrong_line_and_bad_commit():
    msg = m.itch_add(43, b"S", 100, m.SYMBOL, 1501000)   #over the limit
    payload, why = m.verdict(msg)
    order = m.frame_of(payload, True)                    #but committed
    s, _, _ = build(msg, order, False)                   #with abort high
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "x.sr")
        c.write_sr(p, RATE, s)
        r = c.analyse(p)
    bad = r["rows"][0]["bad"]
    assert any("abort high" in b for b in bad)
    assert any("rejects" in b for b in bad)


def test_bench_burst():
    here = os.path.dirname(os.path.abspath(__file__))
    r = c.analyse(os.path.join(here, "..", "docs", "captures", "burst.sr"))
    assert r["problems"] == []
    assert [row["why"] for row in r["rows"]] == \
        ["", "price", "fcs", "limits", "", "", "", "", "risk"]
    assert all(0.2e-6 < row["latency"] < 0.26e-6 for row in r["rows"])


def test_bench_burst_lse():
    here = os.path.dirname(os.path.abspath(__file__))
    r = c.analyse(os.path.join(here, "..", "docs", "captures", "burst_lse.sr"), venue="lse")
    assert r["problems"] == []
    assert [row["why"] for row in r["rows"]] == \
        ["", "price", "fcs", "limits", "", "", "", "risk", "risk"]
    assert all(0.2e-6 < row["latency"] < 0.26e-6 for row in r["rows"])


if __name__ == "__main__":
    for name, f in list(globals().items()):
        if name.startswith("test_"):
            f()
    print("ok")
