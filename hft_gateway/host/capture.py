#checks a pulseview capture of the header against the model
#  python3 capture.py burst.sr [--venue lse] [--plot burst.png]
import argparse
import configparser
import re
import sys
import zipfile

import model as m

CH = dict(sck=0, mosi=1, cs_n=2, ord_tx=3, spec=4, risk_ok=5, commit=6, abort=7)


def read_sr(path):
    z = zipfile.ZipFile(path)
    meta = configparser.ConfigParser()
    meta.read_string(z.read("metadata").decode())
    dev = meta["device 1"]
    rate = dev["samplerate"].split()
    scale = {"hz": 1, "khz": 1e3, "mhz": 1e6, "ghz": 1e9}[(rate[1] if len(rate) > 1 else "hz").lower()]
    rate = float(rate[0]) * scale
    unit = int(dev.get("unitsize", "1"))
    base = dev.get("capturefile", "logic-1")
    parts = sorted((n for n in z.namelist() if re.fullmatch(re.escape(base) + r"-\d+", n)),
                   key=lambda n: int(n.rsplit("-", 1)[1]))
    raw = b"".join(z.read(n) for n in parts)
    if unit == 1:
        return rate, raw
    return rate, [int.from_bytes(raw[i:i + unit], "little") for i in range(0, len(raw), unit)]


def write_sr(path, rate, samples, names=None):
    names = names or list(CH)
    meta = "[global]\nsigrok version=0.5.2\n\n[device 1]\ncapturefile=logic-1\n" \
           "total probes=%d\nsamplerate=%d Hz\ntotal analog=0\n" % (len(names), int(rate))
    meta += "".join("probe%d=%s\n" % (i + 1, n) for i, n in enumerate(names))
    meta += "unitsize=1\n"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("version", "2")
        z.writestr("metadata", meta)
        z.writestr("logic-1-1", bytes(samples))


def bit(s, ch):
    return (s >> ch) & 1


def spi_frames(samples):
    out, cur, edges, acc, n = [], bytearray(), [], 0, 0
    prev = samples[0]
    for i in range(1, len(samples)):
        s = samples[i]
        cs, pcs = bit(s, CH["cs_n"]), bit(prev, CH["cs_n"])
        if not cs and pcs:
            cur, edges, acc, n = bytearray(), [], 0, 0
        if not cs and bit(s, CH["sck"]) and not bit(prev, CH["sck"]):
            edges.append(i)
            acc = (acc << 1) | bit(s, CH["mosi"])
            n += 1
            if n == 8:
                cur.append(acc & 0xFF)
                acc, n = 0, 0
        if cs and not pcs and edges:
            out.append((bytes(cur), edges))
        prev = s
    return out


def uart_bytes(samples, rate, baud):
    spb = rate / baud
    ch = CH["ord_tx"]
    out, i, n = [], 1, len(samples)
    while i < n:
        if not bit(samples[i], ch) and bit(samples[i - 1], ch):
            mid = lambda k: int(i + (k + 0.5) * spb)
            if mid(9) >= n:
                break
            if not bit(samples[mid(0)], ch) and bit(samples[mid(9)], ch):
                v = sum(bit(samples[mid(k + 1)], ch) << k for k in range(8))
                out.append((v, i))
                i = mid(9)
                continue
        i += 1
    return out


def orders(ub, venue="nasdaq"):
    n = m.frame_len(venue)
    out, i = [], 0
    while i + n <= len(ub):
        f = bytes(b for b, _ in ub[i:i + n])
        st = m.check_frame(f, venue)
        if st is None:
            i += 1
            continue
        out.append((f, st, ub[i][1], ub[i + n - 1][1]))
        i += n
    return out


def analyse(path, baud=115200, symbol=None, limit=None, venue="nasdaq"):
    rate, s = read_sr(path)
    feed = spi_frames(s)
    ords = orders(uart_bytes(s, rate, baud), venue)
    e = (23 if venue == "lse" else 32) * 8 - 1    #the trigger's last bit
    rows, problems = [], []
    fi = 0
    for f, st, t0, t1 in ords:
        while fi + 1 < len(feed) and len(feed[fi + 1][1]) > e and feed[fi + 1][1][e] < t0:
            fi += 1
        msg, edges = feed[fi] if feed else (b"", [])
        lat = (t0 - edges[e]) / rate if len(edges) > e and edges[e] < t0 else None
        mid = t1 - int(rate / baud)
        line = "commit" if bit(s[mid], CH["commit"]) else "abort" if bit(s[mid], CH["abort"]) else "-"
        r = dict(seq=None, status=st, line=line, latency=lat, why="")
        bad = []
        if (st == "good") != (line == "commit"):
            bad.append("%s frame with %s high" % (st, line))
        v = m.verdict(msg, symbol=symbol, limit=limit, venue=venue) if msg else None
        if v is None:
            bad.append("no matching feed frame")
        else:
            payload, why = v
            r["why"] = why or ("risk" if st == "stomped" else "")
            if f[:m.VENUES[venue]["order"]] != payload:
                bad.append("order differs from the model")
            if st == "good" and why:
                bad.append("committed what the model rejects")
            r["seq"] = m.parse_feed(msg, venue)["ref"] & 0xFFFFFFFF
            if lat is None or lat > 20e-6:
                bad.append("no trigger edge before it")
        r["bad"] = bad
        rows.append(r)
        problems += bad
    return dict(rate=rate, samples=len(s), feed=len(feed), rows=rows, problems=problems)


def plot(path, out, baud=115200, t_from=None, t_to=None, venue="nasdaq"):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rate, s = read_sr(path)
    a = 0 if t_from is None else int(t_from * rate)
    b = len(s) if t_to is None else int(t_to * rate)
    names = ["feed_sck", "feed_mosi", "feed_cs_n", "ord_tx", "spec", "risk_ok",
             "tx_commit", "tx_abort"]
    surface, ink, muted = "#fcfcfb", "#0b0b0b", "#52514e"
    blue, good, bad = "#2a78d6", "#0ca30c", "#d03b3b"
    colour = [muted, ink, ink, ink, blue, muted, good, bad]

    step = max(1, (b - a) // 20000)
    idx = list(range(a, b, step))
    t = [(i - a) / rate * 1e3 for i in idx]
    fig, ax = plt.subplots(figsize=(11, 4.6), facecolor=surface)
    ax.set_facecolor(surface)
    for k, name in enumerate(names):
        y0 = (len(names) - 1 - k) * 1.5
        ys = [y0 + bit(s[i], k) for i in idx]
        ax.step(t, ys, where="post", lw=0.9, color=colour[k])
        ax.text(-0.01, y0 + 0.5, name, ha="right", va="center", fontsize=9, color=ink,
                transform=ax.get_yaxis_transform())
    for f, st, t0, t1 in orders(uart_bytes(s, rate, baud), venue):
        if a <= t0 < b:
            x0 = (t0 - a) / rate * 1e3
            ax.text(x0, 4 * 1.5 + 1.2, st, fontsize=7, color=muted)
    ax.set_yticks([])
    ax.set_xlabel("ms", color=muted)
    ax.tick_params(colors=muted)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.spines["bottom"].set_color(muted)
    ax.set_xlim(t[0], t[-1])
    fig.tight_layout()
    fig.savefig(out, dpi=150, facecolor=surface)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sr")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--venue", default="nasdaq", choices=sorted(m.VENUES))
    ap.add_argument("--symbol", help="ticker on nasdaq, instrument id on lse")
    ap.add_argument("--limit", type=float, default=150.0)
    ap.add_argument("--plot", metavar="PNG")
    args = ap.parse_args()

    v = m.VENUES[args.venue]
    symbol = m.symbol_of(args.symbol, args.venue) if args.symbol else v["symbol"]
    limit = int(round(args.limit * 1e4 * v["scale"]))
    r = analyse(args.sr, args.baud, symbol, limit, args.venue)
    print("%d samples at %.0f MHz, %d feed frames, %d orders" % (
        r["samples"], r["rate"] / 1e6, r["feed"], len(r["rows"])))
    print("   seq  status    why     line     sck edge to start bit")
    for row in r["rows"]:
        lat = "%.0f ns" % (row["latency"] * 1e9) if row["latency"] is not None else "-"
        print("%6s  %-8s  %-6s  %-7s  %s  %s" % (row["seq"], row["status"], row["why"],
                                                row["line"], lat, "; ".join(row["bad"])))
    lats = [row["latency"] for row in r["rows"] if row["latency"] is not None]
    if lats:
        print("latency %.0f to %.0f ns, one sample is %.0f ns" % (
            min(lats) * 1e9, max(lats) * 1e9, 1e9 / r["rate"]))
    print("problems: %d" % len(r["problems"]))
    if args.plot:
        plot(args.sr, args.plot, args.baud, venue=args.venue)
    sys.exit(1 if r["problems"] else 0)


if __name__ == "__main__":
    main()
