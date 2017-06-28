require "rubygems"
require "mkmf"

unless have_library("kgmod3")
  puts("need libkgmod.")
  puts("refer https://github.com/nysol/mcmd")
  exit 1
end

$LOCAL_LIBS += "-lkgmod3"
create_makefile("nysol/mmethods")

