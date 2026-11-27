# frozen_string_literal: true

# Receives COBS frames from a serial port and prints them.

require "io/console"
require_relative "lib/cobs"

PORT = ENV.fetch("PORT", "ttyV0") # created by virtual_serial.rb

def hex(data, limit: 32)
  shown = data.byteslice(0, limit).unpack("C*").map { |b| format("%02x", b) }.join(" ")
  data.bytesize > limit ? "#{shown} ... (#{data.bytesize} bytes)" : shown
end

trap("TERM") { raise Interrupt }

File.open(PORT, "r+b") do |port|
  port.raw! if port.tty?
  puts "listening on #{PORT}"

  reader = COBS::FrameReader.new
  loop do
    reader.feed(port.readpartial(256)) do |encoded|
      puts "RX:        #{hex(encoded)} 00"
      data = COBS.decode(encoded)
      puts "  decoded: #{hex(data)}"
      puts "  text:    #{data.inspect}" if data.force_encoding(Encoding::UTF_8).valid_encoding? && data.match?(/\A[[:print:]]+\z/)
    rescue COBS::DecodeError => e
      puts "  error:   #{e.message} (frame dropped)"
    end
  end
rescue Interrupt
  # Ctrl-C
end
