require "rubygems"
require "mkmf"

cp="../../.."
libMver="2"
modMver="2"

#$CPPFLAGS += " -Wall "
$LOCAL_LIBS += " -lstdc++ -lmcmd3 -lkgmod3"
#$LOCAL_LIBS += " -lboost_regex -lboost_system -lboost_filesystem -lboost_thread"

create_makefile("mcsvin")



