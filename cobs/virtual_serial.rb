# frozen_string_literal: true

# Virtual null-modem cable for trying serial communication without hardware.
# Creates two pseudo terminals linked to ./ttyV0 and ./ttyV1;
# bytes written to one come out of the other (like `socat pty pty`).

require "io/console"
require "pty"

LINKS = %w[ttyV0 ttyV1].freeze

trap("TERM") { raise Interrupt }

masters = []
slaves = [] # keep the slave ends open so the masters stay readable

begin
  LINKS.each do |link|
    master, slave = PTY.open
    slave.raw! # no echo, no line editing, no newline translation
    File.delete(link) if File.symlink?(link)
    File.symlink(slave.path, link)
    masters << master
    slaves << slave
    puts "#{link} -> #{slave.path}"
  end

  peer = { masters[0] => masters[1], masters[1] => masters[0] }
  loop do
    readable, = IO.select(masters)
    readable.each do |master|
      peer[master].write(master.readpartial(1024))
    rescue IO::WaitReadable, Errno::EIO
      # nothing to read yet
    end
  end
rescue Interrupt
  # Ctrl-C
ensure
  LINKS.each { |link| File.delete(link) if File.symlink?(link) }
end
