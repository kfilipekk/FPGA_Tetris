#one stock's add orders from a nasdaq itch day on stdin
#  curl -s https://emi.nasdaq.com/ITCH/Nasdaq%20ITCH/01302019.NASDAQ_ITCH50.gz \
#      | python3 itch_cut.py AAPL 3000 > aapl.itch
import gzip
import struct
import sys


def cut(src, out, symbol, want, every=50):
    kept = others = 0
    while kept < want:
        head = src.read(2)
        if len(head) < 2:
            break
        msg = src.read(struct.unpack(">H", head)[0])
        if msg[0:1] != b"A":
            continue
        if msg[24:32] == symbol:
            kept += 1
        else:
            others += 1
            if others % every:
                continue
        out.write(head + msg)
    return kept, others


if __name__ == "__main__":
    symbol = sys.argv[1].encode().ljust(8)[:8]
    want = int(sys.argv[2])
    with gzip.GzipFile(fileobj=sys.stdin.buffer) as src:
        try:
            kept, others = cut(src, sys.stdout.buffer, symbol, want)
        except EOFError:
            kept, others = -1, -1
    print("%d %s adds, %d others seen" % (kept, symbol.decode().strip(), others),
          file=sys.stderr)
