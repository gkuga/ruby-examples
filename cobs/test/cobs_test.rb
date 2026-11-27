# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cobs"

class COBSTest < Minitest::Test
  def bytes(*values)
    values.flatten.pack("C*")
  end

  # Examples from https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
  EXAMPLES = [
    [[], [0x01]],
    [[0x00], [0x01, 0x01]],
    [[0x00, 0x00], [0x01, 0x01, 0x01]],
    [[0x00, 0x11, 0x00], [0x01, 0x02, 0x11, 0x01]],
    [[0x11, 0x22, 0x00, 0x33], [0x03, 0x11, 0x22, 0x02, 0x33]],
    [[0x11, 0x22, 0x33, 0x44], [0x05, 0x11, 0x22, 0x33, 0x44]],
    [[0x11, 0x00, 0x00, 0x00], [0x02, 0x11, 0x01, 0x01, 0x01]],
    [(0x01..0xFE).to_a, [0xFF, *(0x01..0xFE)]],
    [[0x00, *(0x01..0xFE)], [0x01, 0xFF, *(0x01..0xFE)]],
    [(0x01..0xFF).to_a, [0xFF, *(0x01..0xFE), 0x02, 0xFF]],
    [[*(0x02..0xFF), 0x00], [0xFF, *(0x02..0xFF), 0x01, 0x01]],
    [[*(0x03..0xFF), 0x00, 0x01], [0xFE, *(0x03..0xFF), 0x02, 0x01]],
  ].freeze

  EXAMPLES.each_with_index do |(decoded, encoded), i|
    define_method("test_encode_example_#{i + 1}") do
      assert_equal bytes(encoded), COBS.encode(bytes(decoded))
    end

    define_method("test_decode_example_#{i + 1}") do
      assert_equal bytes(decoded), COBS.decode(bytes(encoded))
    end
  end

  def test_round_trip_random
    rng = Random.new(1)
    1000.times do
      data = rng.bytes(rng.rand(0..1000))
      encoded = COBS.encode(data)
      refute_includes encoded, COBS::DELIMITER
      assert_operator encoded.bytesize, :<=, data.bytesize + (data.bytesize / 254) + 1
      assert_equal data, COBS.decode(encoded)
    end
  end

  def test_decode_rejects_zero
    assert_raises(COBS::DecodeError) { COBS.decode(bytes(0x03, 0x11, 0x00)) }
  end

  def test_decode_rejects_truncated_block
    assert_raises(COBS::DecodeError) { COBS.decode(bytes(0x05, 0x11, 0x22)) }
  end

  def test_frame_reader_handles_split_chunks
    stream = COBS.frame("hello") + COBS.frame("\x00world\x00")
    reader = COBS::FrameReader.new
    frames = []
    stream.each_char { |c| reader.feed(c) { |f| frames << COBS.decode(f) } }
    assert_equal ["hello".b, "\x00world\x00".b], frames
  end

  def test_frame_reader_skips_empty_frames
    reader = COBS::FrameReader.new
    frames = []
    reader.feed("\x00\x00".b + COBS.frame("a") + "\x00".b) { |f| frames << COBS.decode(f) }
    assert_equal ["a".b], frames
  end

  def test_frame_reader_drops_oversized_frame
    reader = COBS::FrameReader.new(max_frame_size: 4)
    frames = []
    reader.feed(COBS.frame("too long") + COBS.frame("ok")) { |f| frames << COBS.decode(f) }
    assert_equal ["ok".b], frames
  end
end
