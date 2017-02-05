#!/usr/bin/env ruby
require "rubygems"
require "nysol/mcmd"

$version="1.0"
$revision="###VERSION###"

def help
STDERR.puts <<EOF
----------------------------
mtempclean.rb version #{$version}
----------------------------
概要) mtempで作成される一時ファイルおよびディレクトリを削除する
用法) mtempclean.rb [-save]
  -save   : 削除する前に、圧縮補完する
EOF
exit
end

def ver()
	$revision ="0" if $revision =~ /VERSION/
	STDERR.puts "version #{$version} revision #{$revision}"
	exit
end

help() if ARGV[0]=="--help"
ver()  if ARGV[0]=="--version"

args=MCMD::Margs.new(ARGV,"-save")
save=args.bool("-save")
wf=MCMD::Mtemp.new
wf.forceDel(save)

