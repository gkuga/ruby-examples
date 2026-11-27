# cobs

Framing serial messages with COBS (Consistent Overhead Byte Stuffing).
Uses only the Ruby standard library (no gems).

So that it runs without hardware, `virtual_serial.rb` creates a virtual serial cable
(a pair of pseudo terminals) connecting `ttyV0` (receiver side) and `ttyV1` (sender side).

| File | Description |
| --- | --- |
| [lib/cobs.rb](lib/cobs.rb) | COBS encode/decode, and `FrameReader`, which splits a byte stream into frames |
| [virtual_serial.rb](virtual_serial.rb) | Virtual serial cable (like `socat pty pty`) |
| [sender.rb](sender.rb) | Sends a few messages as COBS frames |
| [receiver.rb](receiver.rb) | Receives frames, decodes them and prints them |
| [test/cobs_test.rb](test/cobs_test.rb) | Examples from Wikipedia, plus random round-trip tests |

## Run

```sh
make test           # tests
make run-serial     # terminal 1: create ./ttyV0 <-> ./ttyV1
make run-receiver   # terminal 2: receive on ttyV0
make run-sender     # terminal 3: send from ttyV1
```

With real hardware (a USB serial adapter, for example), set `PORT`, as in
`PORT=/dev/tty.usbserial-XXXX make run-receiver`. These scripts do not set the baud rate,
so set it with `stty` first
(macOS: `stty -f /dev/tty.usbserial-XXXX 115200`, Linux: `stty -F /dev/ttyUSB0 115200`).

## Example output

Sender:

```
data:    11 22 00 33
  TX:    03 11 22 02 33 00
```

Receiver:

```
RX:        03 11 22 02 33 00
  decoded: 11 22 00 33
```

## Why COBS

A serial line is just a stream of bytes, so the receiver needs a way to tell where one
message ends and the next begins. Common approaches:

| Approach | Problem |
| --- | --- |
| Length field at the start | If one byte is lost, every following boundary is off and the receiver cannot recover |
| Idle time between frames (Modbus RTU, for example) | Depends on timing; breaks when the OS or a USB adapter buffers data |
| Delimiter + escaping (SLIP, HDLC, for example) | Depending on the data, the size can double |

COBS rewrites the data so that it contains no 0x00. 0x00 can then delimit frames: the
receiver only **buffers until a 0x00 arrives and decodes**, and after corruption it
resyncs at the next 0x00. The overhead is at most 1 byte per 254 bytes plus 1 byte,
a fixed bound regardless of the data.

## Reading a frame

Encoded data is a sequence of blocks. Each block is a **code byte N** followed by
**N-1 non-zero data bytes**.

- N < 0xFF: the data bytes were followed by one 0x00 in the original data
  (in the last block, the end of the frame stands for it)
- N = 0xFF: 254 data bytes, with no 0x00 after them

```
original: 11 22 00 33

03 11 22 | 02 33 | 00
 |  └──┘    |  └    └ delimiter (end of frame)
 |   |      └ next block: code 2 = 1 data byte
 |   └ 2 data bytes
 └ code 3 = 2 data bytes, followed by a 0x00
```

In other words, the code byte is the distance to the next 0x00.

## Things to try

- `make run-sender-corrupt` simulates a frame that is only partly delivered.
  The broken frame has no delimiter, so it merges with the next frame and both are dropped
  with a decode error. The frame after that is received normally: the receiver resyncs at
  the next 0x00.
- Depending on how a frame is broken, decoding may succeed and **return wrong data**.
  COBS only delimits frames; it does not detect errors in the data. Real protocols add a
  CRC or similar to the data before encoding.
- The 300-byte message is split into an `ff ...` block (254 bytes) and the rest.
  On the receiver, `RX` is 302 bytes + delimiter = 303 bytes: only 3 bytes of overhead.
- If the receiver starts late, it may read the first frame from the middle and see it
  broken. The sender sends one 0x00 first so the receiver discards whatever it has buffered.

## References

- [Consistent Overhead Byte Stuffing - Wikipedia](https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing)
- Stuart Cheshire, Mary Baker. "Consistent Overhead Byte Stuffing". IEEE/ACM Transactions on Networking, 1999
