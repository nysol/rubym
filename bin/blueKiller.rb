#!/usr/bin/env ruby

if ARGV.size!=1
puts "usage) macのメモリ非使用領域を定期的に解放する。"
puts "#{$0} sleep間隔(sec)"
puts "#{$0} 120"
exit
end

sleeping=ARGV[0].to_i

while true
	print "purging start (#{Time.new})..."
	system "purge"
	puts "done. sleeping #{sleeping} sec..."
	sleep(sleeping)
end
