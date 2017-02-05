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
meach.rb version #{$version}
----------------------------
概要) 指定したディレクトリに格納された全ファイルに対して同じ処理を行う。
      入力ファイル毎に結果を出力するか、全ての結果を一つのファイルに出力するかを選択できる。
特徴) mcatと同様の動きをするが、各入力ファイルの属性(ファイル名やサイズ、更新日時など)を扱うことが可能である点が異なる。
      * 処理の指定はコマンドラインを文字列として与え、そのままシェルに渡され実行される(入力ファイル毎に)。
      * MCMDだけでなく、実行環境で利用できるコマンドは全て利用可能。
      * 入力データの形式は問わないので、XMLや画像などあらゆるデータを入力ファイルとして扱うことが可能。
      * ただし、出力はo=の場合はCSVでなければならない。O=の場合はどのようなフォーマットであってもよい。

用法) meach.rb i= [o=|O=] cmd= [try=] [--help]

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
  mp=     : 実行するプロセス数（default:1）

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

$ meach.rb i=indat/*.csv o=out1.csv cmd='msetstr v=##date##,##time##,##size## a=date,time,size i=##file## | mcut f=a,b,date,time,size'

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

def finalact(r_typ,iname,oname,first)
	cmdln = "mcat i=#{iname} "
	case r_typ
	when 1
		cmdln += " -nfno >" unless first
		cmdln += "> #{oname}" 
	when 5
		cmdln += " -nfno" unless first 
	else
		return 
	end

	system(cmdln)
	
end


help() if ARGV[0]=="--help" or ARGV.size <= 0
ver()  if ARGV[0]=="--version"

args=MCMD::Margs.new(ARGV,"i=,o=,O=,cmd=,try=,mp=,-mcmdenv,-stscheck","i=,cmd=")

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
mp     = args.int("mp=",1)
stschk = args.bool("-stscheck")
tim = stschk ? 5 : -1 

fF = true

#################################################
#実行パターンは6とおり(1-6)
# mp  : 1 || not_1
# out : Dir(O=) || file(o=) || stdout
#################################################
# 1: out=file   mp=not_1 
# 2: out=file   mp=1 
# 3: out=Dir    mp=not_1 
# 4: out=Dir    mp=1 
# 5: out=stdout mp=not_1 
# 6: out=stdout mp=1 
#################################################
run_type = ofile ? 1 : opath ? 3 : 5
run_type+=1 if mp==1



files=Dir[ifiles]
raise "#ERROR# file not found matching wildcard `#{ifiles}'" if files.size==0 
MCMD::mkDir(opath) if opath 

runlist = Hash.new
first = true

wfx=MCMD::Mtemp.new
outfname = []
mp.times{ outfname << wfx.file }

ttl    = files.size
nowcnt = 0 
mpm = MCMD::MparallelManager.new(mp,tim)
mpm.runStateCheker

files.each{|file|
	break if try && nowcnt >= try
	cmd2,name = make_scp(cmd,file)
	nowlane = mpm.getLane(false) # ここでは必ず空きがある
	pid=fork{
		#################################################
		# 1: out=file   mp=not_1 
		# 2: out=file   mp=1 
		# 3: out=Dir    mp=not_1 
		# 4: out=Dir    mp=1 
		# 5: out=stdout mp=not_1 
		# 6: out=stdout mp=1 
		#################################################
		case run_type
		when 1,5
			cmd2+=" > #{outfname[nowlane]}"
		when 2
			if nowcnt==0 then
				cmd2 += " | mfldname -q > #{ofile}" 
			else
				cmd2 += " -nfno >> #{ofile}" unless nowcnt==0 
			end
		when 3,4
			cmd2+=" >#{opath}/#{name}"
		when 6
			if nowcnt==0 then
				cmd2 += " | mfldname -q " 
			else
				cmd2 += " -nfno "
			end
		end
		system cmd2
	}
	nowcnt+=1
	MCMD::msgLog("meach.rb start #{file} (#{nowcnt}/#{ttl})")
	mpm.addPid(pid,nowlane) 
	if mpm.emptyLQ? then
		rpidList = mpm.waitLane
		rpidList.each{|nextAno|
			finalact(run_type,outfname[nextAno],ofile,fF)
			fF=false
		}
	end

}
rpidList = mpm.waitall
rpidList.each{|nextAno|
	finalact(run_type,outfname[nextAno],ofile,fF)
	fF=false
}

# 終了メッセージ
MCMD::endLog(args.cmdline)

