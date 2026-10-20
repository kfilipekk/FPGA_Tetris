#the exchange side on made up line captures, run with plain python
import random

import exchange as x
import model as m


def order(seq, kind, good=None):
    payload, why = m.verdict(m.gen_message(seq, kind))
    return m.frame_of(payload, why == "" if good is None else good)


def test_hunt_through_noise():
    random.seed(7)
    frames = [order(k, k) for k in (1, 2, 3, 4, 6)]
    line = bytearray(b"\x00\xffO\x12")
    for f in frames:
        line += f + bytes(random.getrandbits(8) for _ in range(random.randint(0, 5)))
    got, rest = x.hunt(line)
    assert [f for f, _ in got] == frames
    assert [s for _, s in got] == ["good", "stomped", "stomped", "stomped", "good"]
    assert len(rest) < m.FRAME_LEN


def test_split_reads():
    line = order(1, 1) + order(6, 6)
    buf, got = bytearray(), []
    for i in range(0, len(line), 7):
        buf += line[i:i + 7]
        fr, buf = x.hunt(buf)
        got += fr
    assert len(got) == 2


def test_judge_burst():
    whys = [x.judge(order(k, k), m.check_frame(order(k, k)))["why"] for k in (1, 2, 3, 4, 6)]
    assert whys == ["", "price", "fcs", "limits", ""]
    #a good one stomped by the bucket is fine
    r = x.judge(order(7, 7, good=False), "stomped")
    assert r["why"] == "risk" and not r["bad"]


def test_judge_catches_breaks():
    #a commit the model rejects
    r = x.judge(order(2, 2, good=True), "good")
    assert any("rejects" in b for b in r["bad"])
    assert any("limit" in b for b in r["bad"])
    #an order for a message that never triggers
    payload = m.ouch_enter(m.token_of((5 << 48) | 5), 100, m.SYMBOL, 1499000)
    r = x.judge(m.frame_of(payload, False), "stomped")
    assert r["bad"]


def test_stream_clean():
    n = 0
    for s in range(3000):
        v = m.verdict(m.gen_message(s, 0))
        if v is None:
            continue
        f = m.frame_of(v[0], v[1] == "")
        r = x.judge(f, m.check_frame(f))
        assert not r["bad"], (s, r)
        n += 1
    assert n > 500


def test_lse():
    def lorder(seq, kind, good=None):
        payload, why = m.verdict(m.gen_message(seq, kind, venue="lse"), venue="lse")
        return m.frame_of(payload, why == "" if good is None else good)
    frames = [lorder(k, k) for k in (1, 2, 3, 4, 6)]
    got, _ = x.hunt(bytearray(b"\x02\x00" + b"".join(frames)), "lse")
    assert [f for f, _ in got] == frames
    whys = [x.judge(f, st, venue="lse")["why"] for f, st in got]
    assert whys == ["", "price", "fcs", "limits", ""]
    assert x.judge(lorder(2, 2, good=True), "good", venue="lse")["bad"]
    assert x.hunt(bytearray(b"".join(frames)), "nasdaq")[0] == []


if __name__ == "__main__":
    for name, f in list(globals().items()):
        if name.startswith("test_"):
            f()
    print("ok")
