#!/usr/bin/env ruby
# encoding: utf-8
#/* ////////// LICENSE INFO ////////////////////
#
# * Copyright (C) 2013 by NYSOL CORPORATION
# *
# * Unless you have received this program directly from NYSOL pursuant
# * to the terms of a commercial license agreement with NYSOL, then
# * this program is licensed to you under the terms of the GNU Affero General
# * Public License (AGPL) as published by the Free Software Foundation,
# * either version 3 of the License, or (at your option) any later version.
# * 
# * This program is distributed in the hope that it will be useful, but
# * WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF 
# * NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
# *
# * Please refer to the AGPL (http://www.gnu.org/licenses/agpl-3.0.txt)
# * for more details.
#
# ////////// LICENSE INFO ////////////////////*/

require "rubygems"
require "nysol/mcmd"
require "nysol/mparallelmanager"


$version="1.0"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
mdistcopy.rb version #{$version}
----------------------------
概要) distcopyプログラム i=path
      データを転送するプログラム
特徴) i=指定したファイル
用法) mdistfile.rb i=
  i=      : ソース
EOF
exit
end

def ver()
	$revision ="0" if $revision =~ /VERSION/
	STDERR.puts "version #{$version} revision #{$revision}"
	exit
end

help() if ARGV[0]=="--help" or ARGV.size <= 0
ver()  if ARGV[0]=="--version"

args=MCMD::Margs.new(ARGV,"i=,pclist=,mp=","i=")

mpLim  = args.int("mp=",4)
ifiles = args.str("i=")
pclist = args.str("pclist=","/etc/pclist")

pcM   = MCMD::MpcManager.new(pclist)
tempC = MCMD::Mtemp.new
tPath = tempC.path
cPath = ENV['PWD']

# HOMEからのパスで圧縮
ifiles.split(",").each{|fn|
	fnL = File.expand_path(fn)
	fnH = fnL.gsub(/^#{ENV['HOME']}\//,"")  
	tarF = "#{tempC.file}.tar.gz"

	if fnH==fnL then
		system("tar czvf #{tarF} ")	
	else
		system("tar czvf #{tarF} -C #{ENV['HOME']} #{fnH}")
	end
	flist = Array.new(pcM.pcCount,tarF)
	flist.meachc([pcM.pcCount,1]){|fn|
		fn.gsub!(/^\//,"")
		if fnH==fnL then
			system("tar xzvf #{fn} -C /")
		else
			system("tar xzvf #{fn} -C #{ENV['HOME']}")
		end
	}
}

# 終了メッセージ
MCMD::endLog(args.cmdline)

