#reference model, nasdaq itch/ouch and lse mitch/native
import struct
import zlib

ORDER_QTY = 100
MAX_QTY = 500
FIRM = b"FPGA"
NSCEN = 10


def inst(n):
    return struct.pack(">Q", n)


#prices are integers, 4 decimals on nasdaq and 8 on lse
VENUES = {
    "nasdaq": dict(feed=36, order=49, scale=1, symbol=b"AAPL    ",
                   stocks=[b"AAPL    ", b"MSFT    ", b"NVDA    "]),
    "lse": dict(feed=44, order=125, scale=10000, symbol=inst(1001),
                stocks=[inst(1001), inst(1002), inst(1003)]),
}
for _v in VENUES.values():
    _s = _v["scale"]
    _v.update(limit=1500000 * _s, px_lo=1000000 * _s, px_hi=2000000 * _s,
              max_notional=500000000 * _s, center=1500000 * _s)

SYMBOL = VENUES["nasdaq"]["symbol"]
LIMIT = VENUES["nasdaq"]["limit"]
PX_LO, PX_HI = VENUES["nasdaq"]["px_lo"], VENUES["nasdaq"]["px_hi"]
MAX_NOTIONAL = VENUES["nasdaq"]["max_notional"]
CENTER = VENUES["nasdaq"]["center"]
ITCH_LEN = 36
OUCH_LEN = 49
FRAME_LEN = OUCH_LEN + 4


def fcs(payload):
    return struct.pack("<I", zlib.crc32(payload))


def stomp(payload):
    return bytes(b ^ 0xFF for b in fcs(payload))


def _with_fcs(msg, bad):
    f = bytearray(fcs(msg))
    if bad:
        f[0] ^= 1
    return msg + bytes(f)


def itch_add(ref, side, shares, stock, price, ts=0, locate=1, tracking=0, bad=False):
    msg = struct.pack(">cHH6sQcI8sI", b"A", locate, tracking, ts.to_bytes(6, "big"),
                      ref, side, shares, stock, price)
    return _with_fcs(msg, bad)


def mitch_add(ref, side, shares, instrument, price, ts=0, bad=False):
    msg = struct.pack("<BcIQcIIBBQB10s", 44, b"A", ts & 0xFFFFFFFF, ref, side, shares,
                      instrument, 0, 0, price, 0, b" " * 10)
    return _with_fcs(msg, bad)


def ouch_enter(token, qty, stock, price):
    return struct.pack(">c14scI8sII4sccc", b"O", token, b"B", qty, stock, price, 0,
                       FIRM, b"Y", b"P", b"N") + struct.pack(">Icc", 0, b"N", b"R")


def lse_new_order(token, qty, instrument, price):
    return (struct.pack("<bhc", 2, 122, b"D") + token.ljust(20, b"\0") + bytes(21)
            + struct.pack("<BiBBBBIBiiqBBBBqBIIBiIi", 3, instrument, 0x04, 0, 2, 3, 0, 1,
                          qty, qty, price, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            + bytes(16))


def token_of(ref, venue="nasdaq"):
    if venue == "lse":
        return b"%016X" % (ref & ((1 << 64) - 1))
    return b"%014X" % (ref & ((1 << 56) - 1))


def ref_of(token):
    return int(token.rstrip(b"\0"), 16)


def xs(x):
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF
    return x


def gen_fields(seq, kind, venue="nasdaq"):
    v = VENUES[venue]
    side, sym, shares, bad = b"S", 0, 100, False
    if kind == 0:
        r1 = xs(seq ^ 0x9E3779B9)
        r2 = xs(r1)
        side = b"S" if r1 & 1 else b"B"
        sym = {3: 2, 2: 1}.get((r1 >> 1) & 3, 0)
        shares = 50 + ((r1 >> 3) & 0x3FF)
        price = 100 if ((r1 >> 13) & 0x1F) == 0 else 1500000 - 2048 + (r2 & 0xFFF)
        bad = ((r2 >> 12) & 0xF) == 0
    elif kind == 1:
        price = 1499000
    elif kind == 2:
        price = 1501000
    elif kind == 3:
        price, bad = 1498000, True
    elif kind == 4:
        price = 100
    elif kind == 5:
        price, sym = 1499000, 1
    else:
        price = 1499500
    ref = (kind << 48) | seq
    return dict(ref=ref, side=side, shares=shares, stock=v["stocks"][sym],
                price=price * v["scale"], bad=bad, locate=sym + 1)


def gen_message(seq, kind, ts=0, venue="nasdaq"):
    f = gen_fields(seq, kind, venue)
    if venue == "lse":
        return mitch_add(f["ref"], f["side"], f["shares"], int.from_bytes(f["stock"], "big"),
                         f["price"], ts=ts, bad=f["bad"])
    return itch_add(f["ref"], f["side"], f["shares"], f["stock"], f["price"], ts=ts,
                    locate=f["locate"], bad=f["bad"])


def parse_itch(msg):
    if len(msg) < 1 or msg[0:1] != b"A":
        return None
    pad = bytes(msg[:36]) + bytes(max(0, 36 - len(msg)))
    _, _, _, _, ref, side, shares, stock, price = struct.unpack(">cHH6sQcI8sI", pad)
    return dict(ref=ref, side=side, shares=shares, stock=stock, price=price,
                fcs_ok=len(msg) >= 40 and msg[36:40] == fcs(msg[:36]))


def parse_mitch(msg):
    if len(msg) < 2 or msg[0] != 44 or msg[1:2] != b"A":
        return None
    pad = bytes(msg[:44]) + bytes(max(0, 44 - len(msg)))
    _, _, _, ref, side, shares, instrument, _, _, price = struct.unpack("<BcIQcIIBBQ", pad[:33])
    return dict(ref=ref, side=side, shares=shares, stock=inst(instrument), price=price,
                fcs_ok=len(msg) >= 48 and msg[44:48] == fcs(msg[:44]))


def parse_feed(msg, venue="nasdaq"):
    return parse_mitch(msg) if venue == "lse" else parse_itch(msg)


def triggers(msg, symbol=None, venue="nasdaq"):
    v = VENUES[venue]
    symbol = v["symbol"] if symbol is None else symbol
    p = parse_feed(msg, venue)
    need = 23 if venue == "lse" else 32
    if venue == "lse":
        symbol = inst(int.from_bytes(symbol, "big") & 0xFFFFFFFF)
    return p is not None and len(msg) >= need and p["side"] == b"S" and p["stock"] == symbol


def risk_limits(price, qty, venue="nasdaq"):
    v = VENUES[venue]
    return (v["px_lo"] <= price <= v["px_hi"] and 0 < qty <= MAX_QTY
            and price * qty <= v["max_notional"])


def order_payload(ref, qty, symbol, price, venue="nasdaq"):
    if venue == "lse":
        return lse_new_order(token_of(ref, venue), qty,
                             int.from_bytes(symbol, "big") & 0xFFFFFFFF, price)
    return ouch_enter(token_of(ref), qty, symbol, price)


def verdict(msg, tokens=1, kill=False, symbol=None, limit=None, venue="nasdaq"):
    v = VENUES[venue]
    symbol = v["symbol"] if symbol is None else symbol
    limit = v["limit"] if limit is None else limit
    if not triggers(msg, symbol, venue):
        return None
    p = parse_feed(msg, venue)
    qty = min(p["shares"], ORDER_QTY)
    n = v["feed"]
    price = p["price"] if len(msg) >= (33 if venue == "lse" else 36) else 0
    payload = order_payload(p["ref"], qty, symbol, price, venue)
    if len(msg) < n + 4 or not p["fcs_ok"]:
        return payload, "fcs"
    if price > limit:
        return payload, "price"
    if kill:
        return payload, "kill"
    if not risk_limits(price, qty, venue):
        return payload, "limits"
    if tokens <= 0:
        return payload, "tokens"
    return payload, ""


def frame_of(payload, good):
    return payload + (fcs(payload) if good else stomp(payload))


def frame_len(venue="nasdaq"):
    return VENUES[venue]["order"] + 4


def check_frame(frame, venue="nasdaq"):
    n = VENUES[venue]["order"]
    first = b"\x02" if venue == "lse" else b"O"
    if len(frame) != n + 4 or frame[0:1] != first:
        return None
    p, f = frame[:n], frame[n:]
    if f == fcs(p):
        return "good"
    if f == stomp(p):
        return "stomped"
    return None


def parse_order(payload, venue="nasdaq"):
    if venue == "lse":
        token = payload[4:24].rstrip(b"\0")
        instrument, = struct.unpack("<i", payload[46:50])
        side = b"B" if payload[58] == 1 else b"S"
        qty, = struct.unpack("<i", payload[59:63])
        price, = struct.unpack("<q", payload[67:75])
        return dict(token=token, side=side, qty=qty, stock=inst(instrument), price=price)
    t, token, side, qty, stock, price = struct.unpack(">c14scI8sI", payload[:32])
    return dict(token=token, side=side, qty=qty, stock=stock, price=price)


parse_ouch = parse_order


def block(msg):
    return struct.pack(">H", len(msg)) + msg


def config(symbol=SYMBOL, limit=LIMIT, kill=False):
    body = b"C" + symbol.ljust(8)[:8] + struct.pack(">QB", limit, int(kill))
    return body + fcs(body)


def symbol_of(name, venue="nasdaq"):
    if venue == "lse":
        return inst(int(name))
    return name.encode().ljust(8)[:8]
