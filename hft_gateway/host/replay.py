#feeds the board from the pc and checks every order against the model
#  python3 replay.py /dev/ttyUSB1 --synthetic 2000
#  python3 replay.py /dev/ttyUSB1 --itch 01302019.NASDAQ_ITCH50.gz --symbol AAPL --limit 166
#the itch file is nasdaq's own: 2 byte length, then the message, all day long
import argparse
import gzip
import random
import struct
import sys
import time

import exchange as x
import model as m


def read_itch(path, symbol=None, count=None):
    """add orders from a nasdaq itch 5.0 file, each with an fcs on the end"""
    op = gzip.open if path.endswith(".gz") else open
    n = 0
    with op(path, "rb") as f:
        while count is None or n < count:
            head = f.read(2)
            if len(head) < 2:
                return
            msg = f.read(struct.unpack(">H", head)[0])
            if msg[0:1] != b"A" or len(msg) != m.ITCH_LEN:
                continue
            if symbol is not None and msg[24:32] != symbol:
                continue
            n += 1
            yield msg + m.fcs(msg)


def synthetic(count, seed):
    """the on-chip feed's mix, plus cut short and corrupted frames"""
    rnd = random.Random(seed)
    for s in range(count):
        msg = m.gen_message(s, 0, ts=rnd.getrandbits(48))
        r = rnd.random()
        if r < 0.05:
            msg = msg[:rnd.randint(1, 39)]
        elif r < 0.1:
            i = rnd.randrange(40)
            msg = msg[:i] + bytes([msg[i] ^ (1 << rnd.randrange(8))]) + msg[i + 1:]
        yield msg


class Board:
    def __init__(self, port, baud):
        import serial
        self.s = serial.Serial(port, baud, timeout=0.01)
        self.byte_time = 10 / baud
        self.free_at = 0.0   #when the line to the board drains
        self.buf = bytearray()
        self.extra = []      #frames nobody was waiting for

    def send(self, data):
        """paced to the line, so nothing queues up in the usb bridge and an order can
        be waited for from when its message really went out"""
        blk = m.block(data)
        ahead = self.free_at - time.monotonic()
        if ahead > 0.002:
            time.sleep(ahead - 0.002)
        self.s.write(blk)
        self.free_at = max(time.monotonic(), self.free_at) + len(blk) * self.byte_time

    def frames(self, wait):
        """frames off the line within wait seconds of the last byte seen"""
        out, end = [], time.monotonic() + wait
        while time.monotonic() < end:
            got = self.s.read(4096)
            if got:
                self.buf += got
                end = time.monotonic() + wait
            fr, self.buf = x.hunt(self.buf)
            out += fr
        return out

    def order(self, wait=0.3):
        """the next frame, or None"""
        end = max(time.monotonic(), self.free_at) + wait
        while time.monotonic() < end:
            self.buf += self.s.read(4096)
            fr, self.buf = x.hunt(self.buf)
            if fr:
                self.extra += fr[1:]
                return fr[0]
        return None


def check(msg, got, symbol, limit, kill=False):
    """outcome for one message: (name, problem or None)"""
    v = m.verdict(msg, symbol=symbol, limit=limit, kill=kill)
    if v is None:
        return ("none", None) if got is None else ("none", "an order nobody asked for")
    payload, why = v
    if got is None:
        return why or "commit", "no order came back"
    frame, status = got
    if frame[:m.OUCH_LEN] != payload:
        return why or "commit", "order differs from the model"
    if status == "good" and why:
        return why, "committed what the model rejects"
    if status == "stomped" and not why:
        return "risk", None   #the bucket, which the host only sees from outside
    return why or "commit", None


def run(board, msgs, symbol, limit, rate=None, log=print):
    counts, problems, n = {}, 0, 0
    for msg in msgs:
        t0 = time.monotonic()
        board.send(msg)
        expect = m.verdict(msg, symbol=symbol, limit=limit) is not None
        got = board.order() if expect else None
        name, problem = check(msg, got, symbol, limit)
        counts[name] = counts.get(name, 0) + 1
        n += 1
        if problem:
            problems += 1
            log("msg %d: %s (%s)" % (n, problem, name))
        if board.extra:
            problems += len(board.extra)
            log("msg %d: %d orders nobody asked for" % (n, len(board.extra)))
            board.extra = []
        if rate:
            time.sleep(max(0.0, 1 / rate - (time.monotonic() - t0)))
    #anything left on the line is an order nobody asked for
    late = board.frames(0.2)
    problems += len(late)
    return counts, problems, n


def self_test(board, symbol, limit):
    """settings in, a good order, the kill switch, a bad price. returns problems"""
    good = m.itch_add(0xF00D, b"S", 100, symbol, limit - 100)
    over = m.itch_add(0xF00E, b"S", 100, symbol, limit + 100)
    steps = [(False, good, "good"), (False, over, "stomped"),
             (True, good, "stomped"), (False, good, "good")]
    bad = 0
    for kill, msg, want in steps:
        board.send(m.config(symbol, limit, kill))
        time.sleep(0.3)   #a token back between probes
        board.send(msg)
        got = board.order()
        status = got[1] if got else None
        ok = status == want
        bad += not ok
        print("  kill %-5s price %9.4f -> %-8s %s" % (kill, (limit + (100 if msg is over else -100)) / 1e4,
                                                     status, "ok" if ok else "WANT " + want))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--synthetic", type=int, metavar="N")
    ap.add_argument("--itch", metavar="FILE")
    ap.add_argument("--symbol", default="AAPL")
    ap.add_argument("--limit", type=float, default=150.0, help="dollars")
    ap.add_argument("--count", type=int, help="add orders to take from the file")
    ap.add_argument("--only-symbol", action="store_true", help="skip other stocks' adds")
    ap.add_argument("--rate", type=float, help="messages a second, default as fast as it goes")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    symbol = m.symbol_of(args.symbol)
    limit = int(round(args.limit * 1e4))
    board = Board(args.port, args.baud)
    board.frames(0.3)   #drop whatever the on-chip feed left on the line

    print("self test")
    problems = self_test(board, symbol, limit)
    board.send(m.config(symbol, limit, False))

    if args.itch:
        msgs = read_itch(args.itch, symbol if args.only_symbol else None, args.count)
    else:
        msgs = synthetic(args.synthetic or 1000, args.seed)
    t = time.monotonic()
    counts, bad, n = run(board, msgs, symbol, limit, args.rate)
    dt = time.monotonic() - t
    problems += bad

    print("\n%d messages in %.1f s" % (n, dt))
    for k in ("commit", "risk", "price", "fcs", "limits", "none"):
        if k in counts:
            print("  %-7s %d" % (k, counts[k]))
    print("problems: %d" % problems)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
