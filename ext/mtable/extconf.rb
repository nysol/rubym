require "rubygems"
require "mkmf"

cp="../../../"
libMver="2"

$CPPFLAGS += " -Wall -I#{cp}kgmod"
$LOCAL_LIBS += " -L#{cp}kgmod/.libs -L/usr/local/lib -lstdc++ -lkgmod#{libMver}"
if Gem::Platform::local.os =~ /cygwin/
	$LOCAL_LIBS += " -lboost_regex -lboost_system -lboost_filesystem -lboost_thread"
end

create_makefile("mtable")

