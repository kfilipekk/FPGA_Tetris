#reads the order port and checks each frame against the model
#  python3 exchange.py /dev/ttyUSB1
import argparse
import sys
import time

import model as m


def hunt(buf):
    out = []
    i = 0
    while len(buf) - i >= m.FRAME_LEN:
        f = bytes(buf[i:i + m.FRAME_LEN])
        status = m.check_frame(f)
        if status is None:
            i += 1
            continue
        out.append((f, status))
        i += m.FRAME_LEN
    return out, buf[i:]


def judge(frame, status, external=False):
    payload = frame[:m.OUCH_LEN]
    o = m.parse_ouch(payload)
    ref = m.ref_of(o["token"])
    kind, seq = (ref >> 48) & 0xFF, ref & 0xFFFFFFFF
    r = dict(status=status, kind=kind, seq=seq, price=o["price"], qty=o["qty"],
             why="", bad=[])

    if status == "good":
        if o["stock"] != m.SYMBOL or o["side"] != b"B":
            r["bad"].append("wrong stock or side")
        if o["price"] > m.LIMIT:
            r["bad"].append("over the limit")
        if not m.risk_limits(o["price"], o["qty"]):
            r["bad"].append("outside the risk limits")

    if external:
        return r

    v = m.verdict(m.gen_message(seq, kind))
    if v is None:
        r["bad"].append("an order for a message that should not trigger")
        return r
    want, why = v
    r["why"] = why
    if payload != want and not (status == "stomped" and payload[:28] == want[:28]):
        r["bad"].append("payload differs from the model")
    if status == "good" and why:
        r["bad"].append("committed what the model rejects (%s)" % why)
    if status == "stomped" and not why:
        r["why"] = "risk"
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--external", action="store_true", help="feed is not the on-chip one")
    args = ap.parse_args()

    import serial
    s = serial.Serial(args.port, args.baud, timeout=0.1)
    buf = bytearray()
    counts = {}
    goods = []
    errors = 0
    print("   seq kind  status    why     price    qty")
    try:
        while True:
            buf += s.read(4096)
            frames, buf = hunt(buf)
            now = time.monotonic()
            for f, status in frames:
                r = judge(f, status, args.external)
                key = r["why"] or status
                counts[key] = counts.get(key, 0) + 1
                if status == "good":
                    goods.append(now)
                print("%6d %4d  %-8s  %-6s %10.4f %6d  %s" % (
                    r["seq"], r["kind"], status, r["why"], r["price"] / 1e4, r["qty"],
                    "; ".join(r["bad"])))
                errors += bool(r["bad"])
    except KeyboardInterrupt:
        pass
    peak = max((sum(1 for t in goods if a <= t < a + 0.25) for a in goods), default=0)
    print("\n" + ", ".join("%s %d" % kv for kv in sorted(counts.items())))
    print("most good orders in any 250 ms: %d" % peak)
    print("rule breaks: %d" % errors)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
