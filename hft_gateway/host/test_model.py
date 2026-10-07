#the model against the spec layouts, run with plain python
import zlib

import model as m


def test_layouts():
    msg = m.itch_add(0x1234, b"S", 100, b"AAPL    ", 1499000)
    assert len(msg) == 40
    assert msg[0:1] == b"A" and msg[19:20] == b"S" and msg[24:32] == b"AAPL    "
    assert int.from_bytes(msg[32:36], "big") == 1499000
    o = m.ouch_enter(m.token_of(0x1234), 100, b"AAPL    ", 1499000)
    assert len(o) == 49
    assert o[0:1] == b"O" and o[1:15] == b"00000000001234" and o[15:16] == b"B"
    assert o[20:28] == b"AAPL    " and o[36:40] == b"FPGA" and o[48:49] == b"R"


def test_fcs():
    p = b"O" + bytes(range(1, 49))
    good, bad = m.frame_of(p, True), m.frame_of(p, False)
    assert m.check_frame(good) == "good"
    assert m.check_frame(bad) == "stomped"
    assert m.check_frame(good[:-1] + bytes([good[-1] ^ 1])) is None
    #crc over a frame and its good fcs leaves the ethernet residue
    assert zlib.crc32(good) == 0x2144DF1C


def test_verdicts():
    def v(**kw):
        a = dict(ref=1, side=b"S", shares=100, stock=b"AAPL    ", price=1499000)
        a.update(kw)
        return m.verdict(m.itch_add(**a))
    assert v()[1] == ""
    assert v(price=1501000)[1] == "price"
    assert v(bad=True)[1] == "fcs"
    assert v(price=100)[1] == "limits"
    assert v(side=b"B") is None
    assert v(stock=b"AAPX    ") is None
    assert m.verdict(m.itch_add(1, b"S", 100, b"AAPL    ", 1499000), tokens=0)[1] == "tokens"
    assert m.verdict(m.itch_add(1, b"S", 100, b"AAPL    ", 1499000)[:38])[1] == "fcs"
    assert m.verdict(m.itch_add(1, b"S", 100, b"AAPL    ", 1499000)[:30]) is None


def test_burst_script():
    whys = []
    for k in range(1, m.NSCEN + 1):
        r = m.verdict(m.gen_message(k, k))
        whys.append(None if r is None else r[1])
    assert whys == ["", "price", "fcs", "limits", None, "", "", "", "", ""]


def test_stream_mix():
    #the stream hits every path
    seen = set()
    for s in range(2000):
        r = m.verdict(m.gen_message(s, 0))
        seen.add(None if r is None else r[1])
    assert seen == {None, "", "price", "fcs", "limits"}


if __name__ == "__main__":
    for name, f in list(globals().items()):
        if name.startswith("test_"):
            f()
    print("ok")
