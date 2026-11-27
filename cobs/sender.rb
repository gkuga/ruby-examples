# frozen_string_literal: true

# Sends a few COBS frames over a serial port.
#
#   ruby sender.rb            # send normal frames
#   ruby sender.rb --corrupt  # also send a broken frame to see the receiver resync

require "io/console"
require_relative "lib/cobs"

PORT = ENV.fetch("PORT", "ttyV1") # the other end of the virtual cable

MESSAGES = [
  "Hello, COBS!",
  "\x11\x22\x00\x33".b,                 # contains a zero byte
  "\x00\x00\x00".b,                     # only zeros
  (1..300).map { |i| i % 256 }.pack("C*"), # longer than one 254-byte block
].freeze

def hex(data, limit: 32)
  shown = data.byteslice(0, limit).unpack("C*").map { |b| format("%02x", b) }.join(" ")
  data.bytesize > limit ? "#{shown} ... (#{data.bytesize} bytes)" : shown
end

def send_frame(port, data)
  frame = COBS.frame(data)
  puts "data:    #{hex(data)}"
  puts "  TX:    #{hex(frame)}"
  port.write(frame)
end

File.open(PORT, "r+b") do |port|
  port.raw! if port.tty?
  port.sync = true

  # A leading delimiter flushes anything left in the receiver's buffer.
  port.write(COBS::DELIMITER)

  MESSAGES.each { |message| send_frame(port, message) }

  if ARGV.include?("--corrupt")
    frame = COBS.frame("lost in the middle")
    broken = frame.byteslice(0, 8) # the rest of the frame is lost
    puts "corrupt: sending only the first #{broken.bytesize} bytes of a frame, then a new frame"
    puts "  TX:    #{hex(broken)}"
    port.write(broken)
    send_frame(port, "after the noise") # merged with the broken bytes, so it is lost too
    send_frame(port, "back in sync")
  end
end
