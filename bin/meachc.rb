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

# 1.2: mp= parameter 追加
$version="1.2"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
meachc.rb version #{$version}
----------------------------
概要) 指定したディレクトリに格納された全ファイルに対して同じ処理を行う。
      入力ファイル毎に結果を出力するか、全ての結果を一つのファイルに出力するかを選択できる。
特徴) mcatと同様の動きをするが、各入力ファイルの属性(ファイル名やサイズ、更新日時など)を扱うことが可能である点が異なる。
      * 処理の指定はコマンドラインを文字列として与え、そのままシェルに渡され実行される(入力ファイル毎に)。
      * MCMDだけでなく、実行環境で利用できるコマンドは全て利用可能。
      * 入力データの形式は問わないので、XMLや画像などあらゆるデータを入力ファイルとして扱うことが可能。
      * ただし、出力はo=の場合はCSVでなければならない。O=の場合はどのようなフォーマットであってもよい。

用法) meachc.rb i= [o=|O=] cmd= [try=] [--help]

  i=      : ワイルドカードを含む入力ファイル名【必須】
  o=      : 出力ファイル名。全ての結果はここで指定したファイルに出力される。
            o=,O=共に省略した場合は,標準出力に出力される。
  O=      : 出力ディレクトリ名。このディレクトリの直下に、各入力ファイルと同じファイル名で出力される。
  cmd=  : コマンドライン
          以下のシンボルは、実行前に入力ファイルの各属性に置換される。
           -----------+-----------------------------------------
            シンボル  | 属性
           -----------+-----------------------------------------
            ##file##  | ファイル名
            ##name##  | ディレクトリ名を除いたファイル名
            ##core##  | ディレクトリ名と拡張子を除いたファイル名
            ##ext##   | ファイル名拡張子
            ##body##  | 拡張子を除いたファイル名
            ##dir##   | ディレクトリ名
            ##apath## | 絶対パス名
            ##date##  | ファイル作成日付
            ##time##  | ファイル作成時刻
            ##size##  | ファイルサイズ
           -----------+-----------------------------------------
  try=    : 実際に実行する入力ファイル数(テスト目的で利用される)(省略すれば全ファイルに対して実行する)
  mpc=    : 実行する端末数（default:3）
  mp=     : 実行するプロセス数（default:2）

詳細)
  o=が指定された場合、cmd=で指定されたコマンドライン文字列は以下の擬似コードに示されるように修正されてshellに渡される。

    cmd: cmd=で指定されたコマンドライン文字列
    ofile: 出力ファイル名
    if 最初のファイル
      cmd = cmd + " >ofile"
    else
      cmd = cmd + " -nfno >>ofile"
    end

  O=が指定された場合の擬似コードは以下の通り。
    cmd: cmd=で指定されたコマンドライン文字列
    opath: 出力ディレクトリ名
    name: 入力ファイル名
    cmd2 = + " >{opath}/name"

  o=もO=も指定されない場合は以下の通りで、標準出力に出力されるので、パイプで接続ことも可能である。
    cmd: cmd=で指定されたコマンドライン文字列
    ofile: 出力ファイル名
    unless 最初のファイル
      cmd = cmd + " -nfno"
    end

必要なrubyライブラリ)
	nysol

例)
indat/a01.csv
a,b,c
A,x,1
A,y,2

indat/a02.csv
a,b,c
B,x,3
B,y,4

indat/a03.csv
a,b,c
C,x,5
C,y,6

$ meachc.rb i=indat/*.csv o=out1.csv cmd='msetstr v=##date##,##time##,##size## a=date,time,size i=##file## | mcut f=a,b,date,time,size'

out1.csv
a,b,date,time,size
A,x,20141114,211722,18
A,y,20141114,211722,18
B,x,20141114,211722,18
B,y,20141114,211722,18
C,x,20141114,211722,18
C,y,20141114,211722,18

# Copyright(c) NYSOL 2012- All Rights Reserved.
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

#############################################################################
# ↑↑↑↑↑　　HELP & VRESION　　↑↑↑↑↑↑↑↑↑↑↑↑↑
#############################################################################

def make_scp(cmd,file)
	atime=File.atime(file)
	time=atime.strftime("%H%M%S")
	date=atime.strftime("%Y%m%d")
	size =File.size(file)
	apath=File.absolute_path(file)
	dir  =File.dirname(file)
	ext  =File.extname(file).sub(".","")
	name =File.basename(file)
	core =name.sub(/\.#{ext}$/,"") 
	body =name.sub(".#{ext}","")
	cmd2=cmd.gsub("##file##",file)
	        .gsub("##name##",name)
	        .gsub("##core##",core)
          .gsub("##time##",time)
          .gsub("##date##",date)
          .gsub("##size##",size.to_s)
          .gsub("##apath##",apath)
          .gsub("##dir##",dir)
          .gsub("##ext##",ext)
          .gsub("##body##",body)
  return cmd2,name
end


args=MCMD::Margs.new(ARGV,"i=,o=,O=,cmd=,try=,mp=,mpc=,-mcmdenv","i=,cmd=")

# mcmdのメッセージは警告とエラーのみ
ENV["KG_VerboseLevel"]="2" unless args.bool("-mcmdenv")

#ワークファイルパス
if args.str("T=")!=nil then
	ENV["KG_TmpPath"] = args.str("T=").sub(/\/$/,"")
end

ifiles = args.str("i=")
ofile  = args.file("o=","w")
opath  = args.str("O=")
cmd    = args.str("cmd=")
try    = args.int("try=")
mpLim = args.int("mp=",4)
mpPC    = args.int("mpc=",4)
pclist    = args.str("pclist=","/etc/pclist")
opath  = "#{opath}/" if opath != nil && opath !~ /\/$/

#################################################
# PC_LIST読み込み
#################################################
pcM = MCMD::MpcManager.new(pclist)
mpPC  = pcM.pcCount if mpPC > pcM.pcCount
mpMax = mpPC * mpLim

#################################################
#実行パターンは3
# out : Dir(O=) || file(o=) || stdout
#################################################
# 1: out=file 
# 2: out=Dir  
# 3: out=stdout 
#################################################
run_type = ofile ? 1 : opath ? 2 : 3


files=Dir[ifiles]
raise "#ERROR# file not found matching wildcard `#{ifiles}'" if files.size==0 
MCMD::mkDir(opath) if opath 

runlist = Hash.new
ttl = files.size

# -----------------------------------------------------
# 作業ディレクトリ決定
# -----------------------------------------------------
tempC=MCMD::Mtemp.new
runScp    = tempC.file
local_WkD = tempC.file
net_WkD   = tempC.file
MCMD::mkDir(local_WkD)


mpm = MCMD::MparallelManagerByFile.new(mpMax,local_WkD)
mpm.runStateCheker


nowcnt = 0 
rtnlist =[]

files.each{|file|
	break if try && counter >= try
	MCMD::msgLog("m2eachc.rb (#{nowcnt}/#{ttl})")

	cmd2,name = make_scp(cmd,file)
	nowlane = mpm.getLane # ここでは必ず空きがある

	pid=fork{
		# データ転送
		stNo = nowlane%mpPC
		net_nowwkD  = "#{net_WkD}/#{nowcnt}" 
		# -----------------------------------------------------
		# スクリプト生成
		# -----------------------------------------------------
		runscp_N = "#{runScp}_#{nowlane}.sh" 
		File.open(runscp_N,"w"){|fpw|
			fpw.puts ("cd #{net_nowwkD}")
			case run_type
			when 1,3
				cmd2 += " > #{net_nowwkD}/#{name}_#{nowcnt}"
			when 2
				cmd2 += " > #{net_nowwkD}/#{name}"
			end
			fpw.puts (cmd2)
			fpw.puts "echo pgmend #{nowcnt} >> #{net_nowwkD}/endlog"
			fpw.puts "ls -lR >> #{net_nowwkD}/endlog"
			fpw.puts "msend.rb i=#{net_nowwkD}/endlog uid=#{pcM.getUID(stNo)} o=#{pcM.localIP}:#{local_WkD}/#{nowlane}.log"
		}
		# -----------------------------------------------------
		# スクリプトファイル&データ転送
		# -----------------------------------------------------
		MCMD::msgLog("m2eachc.rb snddata #{file} (#{nowcnt}/#{ttl})")
		distSrc  = "#{net_nowwkD}/#{File.basename(runscp_N)}"
		MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),runscp_N,distSrc ,pcM.getPWD(stNo))
		MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),file    ,"#{net_nowwkD}/#{file}",pcM.getPWD(stNo))

		# -----------------------------------------------------
		# プログラム実行
		# -----------------------------------------------------
		MCMD::msgLog("m2eachc.rb pgmstart #{file} (#{nowcnt}/#{ttl})")
		MCMD::NetTools.cmdRun(pcM.getIP(stNo),pcM.getUID(stNo),"nohup bash #{distSrc} 1> #{net_nowwkD}/RunLog 2>&1 &")
	}
	rtnlist << [ pcM.getIP(nowlane%mpPC),"#{net_WkD}/#{nowcnt}" ]
	mpm.addNo(nowcnt,nowlane) 
	nowcnt+=1
	Process.detach(pid)
}
mpm.waitall		

case run_type
when 1
	rtnlist.mcollect("#{File.basename(ifiles)}_*",ofile) 
when 2
	rtnlist.mcollect(File.basename(ifiles),opath) 
when 3
	rtnlist.mcollect("#{File.basename(ifiles)}_*",nil) 
end

# 終了メッセージ
MCMD::endLog(args.cmdline)

