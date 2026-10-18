#reference model: message layouts, the on-chip feed and the engine's verdicts
import struct
import zlib

SYMBOL = b"AAPL    "
LIMIT = 1500000            #$150.0000
ORDER_QTY = 100
PX_LO, PX_HI = 1000000, 2000000
MAX_QTY = 500
MAX_NOTIONAL = 500000000
FIRM = b"FPGA"
CENTER = 1500000
NSCEN = 10

ITCH_LEN = 36              #add order, then 4 fcs bytes
OUCH_LEN = 49              #enter order, then 4 fcs bytes
FRAME_LEN = OUCH_LEN + 4


def fcs(payload):
    return struct.pack("<I", zlib.crc32(payload))


def stomp(payload):
    return bytes(b ^ 0xFF for b in fcs(payload))


def itch_add(ref, side, shares, stock, price, ts=0, locate=1, tracking=0, bad=False):
    msg = struct.pack(">cHH6sQcI8sI", b"A", locate, tracking, ts.to_bytes(6, "big"),
                      ref, side, shares, stock, price)
    f = bytearray(fcs(msg))
    if bad:
        f[0] ^= 1
    return msg + bytes(f)


def ouch_enter(token, qty, stock, price):
    return struct.pack(">c14scI8sII4sccc", b"O", token, b"B", qty, stock, price, 0,
                       FIRM, b"Y", b"P", b"N") + struct.pack(">Icc", 0, b"N", b"R")


def token_of(ref):
    return b"%014X" % (ref & ((1 << 56) - 1))


def ref_of(token):
    return int(token, 16)


def xs(x):
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF
    return x


STOCKS = [b"AAPL    ", b"MSFT    ", b"NVDA    "]


def gen_fields(seq, kind):
    """the on-chip feed's message for a sequence number and kind (0 stream, 1-10 burst)"""
    side, sym, shares, bad = b"S", 0, 100, False
    if kind == 0:
        r1 = xs(seq ^ 0x9E3779B9)
        r2 = xs(r1)
        side = b"S" if r1 & 1 else b"B"
        sym = {3: 2, 2: 1}.get((r1 >> 1) & 3, 0)
        shares = 50 + ((r1 >> 3) & 0x3FF)
        price = 100 if ((r1 >> 13) & 0x1F) == 0 else CENTER - 2048 + (r2 & 0xFFF)
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
    return dict(ref=ref, side=side, shares=shares, stock=STOCKS[sym], price=price,
                bad=bad, locate=sym + 1)


def gen_message(seq, kind, ts=0):
    f = gen_fields(seq, kind)
    return itch_add(f["ref"], f["side"], f["shares"], f["stock"], f["price"], ts=ts,
                    locate=f["locate"], bad=f["bad"])


def parse_itch(msg):
    """fields of an add order frame, short ones padded, or None if not one"""
    if len(msg) < 1 or msg[0:1] != b"A":
        return None
    pad = bytes(msg[:36]) + bytes(max(0, 36 - len(msg)))
    _, _, _, _, ref, side, shares, stock, price = struct.unpack(">cHH6sQcI8sI", pad)
    return dict(ref=ref, side=side, shares=shares, stock=stock, price=price,
                fcs_ok=len(msg) >= 40 and msg[36:40] == fcs(msg[:36]))


def triggers(msg, symbol=SYMBOL):
    """an order goes out on this frame: add order, sell side, our stock"""
    p = parse_itch(msg)
    return p is not None and len(msg) >= 32 and p["side"] == b"S" and p["stock"] == symbol


def risk_limits(price, qty):
    return (PX_LO <= price <= PX_HI and 0 < qty <= MAX_QTY
            and price * qty <= MAX_NOTIONAL)


def verdict(msg, tokens=1, kill=False, symbol=SYMBOL, limit=LIMIT):
    """None if no order, else (payload, why) with why '' when it commits"""
    if not triggers(msg, symbol):
        return None
    p = parse_itch(msg)
    qty = min(p["shares"], ORDER_QTY)
    full = len(msg) >= 40
    price = p["price"] if len(msg) >= 36 else 0
    payload = ouch_enter(token_of(p["ref"]), qty, symbol, price)
    if not full or not p["fcs_ok"]:
        return payload, "fcs"
    if price > limit:
        return payload, "price"
    if kill:
        return payload, "kill"
    if not risk_limits(price, qty):
        return payload, "limits"
    if tokens <= 0:
        return payload, "tokens"
    return payload, ""


def frame_of(payload, good):
    return payload + (fcs(payload) if good else stomp(payload))


def check_frame(frame):
    """'good', 'stomped' or None for a frame off the order port"""
    if len(frame) != FRAME_LEN or frame[0:1] != b"O":
        return None
    p, f = frame[:OUCH_LEN], frame[OUCH_LEN:]
    if f == fcs(p):
        return "good"
    if f == stomp(p):
        return "stomped"
    return None


def parse_ouch(payload):
    t, token, side, qty, stock, price = struct.unpack(">c14scI8sI", payload[:32])
    return dict(token=token, side=side, qty=qty, stock=stock, price=price)


def block(msg):
    """a moldudp64 style message block: 2 byte big endian length, then the message"""
    return struct.pack(">H", len(msg)) + msg


def config(symbol=SYMBOL, limit=LIMIT, kill=False):
    """the settings frame the engine takes in band on its feed"""
    body = b"C" + symbol.ljust(8)[:8] + struct.pack(">IB", limit, int(kill))
    return body + fcs(body)


def symbol_of(name):
    return name.encode().ljust(8)[:8]
