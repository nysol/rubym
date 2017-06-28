require "rubygems"
require "mkmf"

unless have_library("kgmod3")
  puts("-----------------------------")
  puts("need libkgmod3.")
  puts("refer https://github.com/nysol/mcmd")
  puts("-----------------------------")
  exit 1
end

$LOCAL_LIBS += "-lkgmod3"
create_makefile("nysol/mcsvout")

