# frozen_string_literal: true

# Consistent Overhead Byte Stuffing (COBS).
#
# COBS rewrites a byte string so that it contains no 0x00 bytes. A 0x00 can then
# mark the end of a frame on a byte stream such as a serial line.
#
# The encoded data is a list of blocks. Each block starts with a code byte N
# (1..255) followed by N-1 non-zero data bytes:
#
#   - N < 0xFF: after the data bytes comes a 0x00 in the original data
#               (except for the last block, where it is implied by the frame end)
#   - N = 0xFF: 254 data bytes and no 0x00 after them
#
# The overhead is at most 1 byte per 254 bytes, plus 1 byte.
module COBS
  DELIMITER = "\x00".b
  MAX_BLOCK = 0xFF

  class DecodeError < StandardError; end

  module_function

  # Encodes +data+ (a String) into a COBS string without the trailing delimiter.
  def encode(data)
    data = data.b
    out = +"".b
    code_index = start_block(out)
    code = 1

    data.each_byte.with_index do |byte, i|
      if byte.zero?
        out.setbyte(code_index, code)
        code_index = start_block(out)
        code = 1
        next
      end

      out << byte
      code += 1
      next unless code == MAX_BLOCK

      out.setbyte(code_index, code)
      # A full block does not imply a zero, so start a new block only if more data follows.
      break if i == data.bytesize - 1

      code_index = start_block(out)
      code = 1
    end

    out.setbyte(code_index, code) if code < MAX_BLOCK
    out
  end

  # Decodes a COBS string (without the delimiter) back into the original data.
  # Raises DecodeError if +data+ is not valid COBS.
  def decode(data)
    data = data.b
    out = +"".b
    i = 0

    while i < data.bytesize
      code = data.getbyte(i)
      raise DecodeError, "unexpected 0x00 at offset #{i}" if code.zero?

      i += 1
      length = code - 1
      if i + length > data.bytesize
        raise DecodeError, "block at offset #{i - 1} needs #{length} bytes, only #{data.bytesize - i} left"
      end

      block = data.byteslice(i, length)
      raise DecodeError, "unexpected 0x00 in block at offset #{i - 1}" if block.include?(DELIMITER)

      out << block
      i += length
      out << DELIMITER if code < MAX_BLOCK && i < data.bytesize
    end

    out
  end

  # Returns a full frame for the wire: encoded data followed by the delimiter.
  def frame(data)
    encode(data) << DELIMITER
  end

  def start_block(out)
    out << "\x00" # placeholder for the code byte
    out.bytesize - 1
  end
  private_class_method :start_block

  # Splits a byte stream into frames at each 0x00.
  #
  #   reader = COBS::FrameReader.new
  #   reader.feed(io.readpartial(256)) { |encoded| ... }
  #
  # Bytes arrive in arbitrary chunks, so a frame may be split across reads;
  # the reader keeps the partial frame until its delimiter arrives.
  # Empty frames (two delimiters in a row) are skipped. Senders often send an
  # extra delimiter first to flush any garbage the receiver may hold.
  class FrameReader
    def initialize(max_frame_size: 4096)
      @buffer = +"".b
      @max_frame_size = max_frame_size
      @dropping = false
    end

    # Feeds received bytes and yields each complete encoded frame (without the delimiter).
    def feed(bytes)
      bytes.b.each_char do |char|
        if char == DELIMITER
          frame = @buffer
          @buffer = +"".b
          yield frame unless frame.empty? || @dropping
          @dropping = false
        elsif @buffer.bytesize >= @max_frame_size
          # Drop an oversized frame and resync at the next delimiter.
          @buffer.clear
          @dropping = true
        elsif !@dropping
          @buffer << char
        end
      end
    end
  end
end
