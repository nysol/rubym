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
msend.rb version #{$version}
----------------------------
概要) データ送信プログラム i=path o=ip:path 
      データを転送するプログラム
特徴) i=指定したファイルをo=に指定したpathにコピーする
用法) msend.rb i= [o=|O=] [uid=]
  i=      : ファイル名
  o=      : 出力ファイル名。全ての結果はここで指定したファイルに出力される。
  O=      : 出力ディレクトリ名。このディレクトリの直下に、各入力ファイルと同じファイル名で出力される。
  uid=    : ユーザ名
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

args=MCMD::Margs.new(ARGV,"i=,o=,O=,uid=,retry=","i=")

ifiles = args.str("i=")
ofile  = args.str("o=")
opath  = args.str("O=")
uid    = args.str("uid=")
pclist = args.str("pclist=","/etc/pclist")

pcM = MCMD::MpcManager.new(pclist)

if !ofile and  !opath then
	STDERR.puts "It is necessary either o= or O= "
	exit
end

i_sep = ifiles.split(":")
i_fn  = i_sep[-1]
i_ip  = i_sep[0] if i_sep.size > 1 

dicF = true if opath 
oname = dicF ? opath : ofile
o_sep = oname.split(":")
o_fn  = o_sep[-1]
o_ip  = o_sep[0] if o_sep.size > 1 

if i_sep.size ==1 and o_sep.size ==1 then
	system("cp #{i_fn} #{o_fn}")
elsif o_sep.size == 1 then 
	MCMD::NetTools.recv(i_ip,uid,i_fn,o_fn,pcM.getPWDbyIP(i_ip))	
elsif i_sep.size == 1 then 
	MCMD::NetTools.send(o_ip,uid,i_fn,o_fn,pcM.getPWDbyIP(o_ip))	
else
	STDERR.puts "Not compatible"
	exit	
end

# 終了メッセージ
MCMD::endLog(args.cmdline)

