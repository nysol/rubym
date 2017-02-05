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

module MCMD

#= 一時ファイル名を扱うクラス
#
#  一時ファイル名の生成と、そのファイルの(自動)削除を行うクラス*。
#  一時ファイル名はfileもしくはpipeメソッドを呼び出すたびに重複なく生成される。
#  fileメソッドでは、ファイル名が生成するだけで、実ファイルは生成されない。
#  一方でpipeメソッドでは、mkfifoコマンドにより名前付きパイプファイルが生成される。
#
#  一時ファイル名の命名規則は以下の通り。
#   "#{@path}/__MTEMP_#{@pid}_#{@oid}_#{@seq}"
#
#  @pid : プロセスID ($$)
#  @oid : オブジェクトID (self.object_id)
#  @seq : オブジェクト内の通し番号 (自動採番で1から始まる)
#  @path   : 以下の優先順位で決まる。
#       1) Mtemp.newの第1引数で指定された値*
#       2) KG_TmpPath環境変数の値
#       3) TMP環境変数の値
#       4) TEMP環境変数の値
#       5) "/tmp"
#       6) "." (カレントパス)
#
#  注*) new第1引数でパス名を明示的に指定した場合、GC時に自動削除されない。
#
#=== メソッド:
# file : 一時ファイル名を返す
# path : 一時ファイル名を格納するパスを返す
# rm   : 実行時点までに生成した一時ファイルを全て削除する。
#
#=== 例1
#  基本利用例
# ------------------------------------------------------
#  require 'mtools'
#
#  tmp=MCMD::Mtemp.new
#  fName1=tmp.file
#  fName2=tmp.file
#  fName3=tmp.file("./xxa")
#  puts fName1 # -> /tmp/__MTEMP_60637_2152301760_0
#  puts fName2 # -> /tmp/__MTEMP_60637_2152301760_1
#  puts fName3 # -> ./xxa
#  File.open(fName1,"w"){|fp| fp.puts "temp1"}
#  File.open(fName2,"w"){|fp| fp.puts "temp2"}
#  File.open(fName3,"w"){|fp| fp.puts "temp3"}
#  # tmpがローカルのスコープを外れると
#  # GCが発動するタイミングで一時ファイルも自動的に削除される。
#  # ただし、fName3は一時ファイル名を直接指定しているの削除されない。
# ------------------------------------------------------
#
#===例2:
#  全ての一時ファイルが自動削除されない例
# ------------------------------------------------------
#  require 'mtools'
#
#  # コンストラクタでパスを指定すると自動削除されない。
#  # (rmメソッドにより削除することはできる。)
#  tmp=MCMD::Mtemp.new(".")
#  fName=tmp.file
#  File.open(fName,"w"){|fp| fp.puts "temp"}
#  # tmpがローカルのスコープを外れGCが発動しても
#  # 一時ファイルは削除されない。
# ------------------------------------------------------
#
#=== 例3:
#  名前付きパイプ名の生成
# ------------------------------------------------------
#  require 'mtools'
#
#  tmp=MCMD::Mtemp.new
#  pName=tmp.pipe
#  system("ls -l #{pName}") # この段階で名前付きパイプファイルが作成されている。
# ->  prw-r--r--  1 user  group  0  7 19 12:20 /tmp/__MTEMP_60903_2152299720_0
#  system("echo 'abc' > #{pName} &") # バックグラウンド実行でnamed pipeに書き込み
#  system("cat <#{pName} &")         # バックグラウンド実行でnamed pipeから読み込み
#  # tmpがローカルのスコープを外れると
#  # GCが発動するタイミングで全ての一時ファイルは自動削除される。
# ------------------------------------------------------
class Mtemp
private

	# ワークファイルを全て消す
	def delAllFiles(path,pid,oid)
		if  @pid == $$.to_s and @oid == self.object_id  then
			Dir["#{path}/__MTEMP_#{@pid}_#{@oid}_*"].each{|dn|
				system "rm -rf #{dn}"
			}
		end
	end


	# デストラクタ呼び出し時にcallされる関数
	class << self
		def callback(path,pid,oid)
			lambda {
				delAllFiles(path,pid,oid)
			}
		end
	end

 	#== コンストラクタ
 	# Mtempオブジェクトを生成する。
	# path: 一時ファイルを格納するディレクトリパス名を指定する。
	#       pathを指定した場合、作成された一時ファイルはGC時に自動削除されない。
	#       pathの指定しなければ、環境変数に設定されたpath名等が利用され、GC時に自動削除される。
	def initialize(path=nil)
		@gcRM=true
		if path
			@path=path
			@gcRM=false
		elsif not ENV["KG_TmpPath"].nil? then
			@path=ENV["KG_TmpPath"]
		elsif not ENV["TMP"].nil? then
			@path=ENV["TMP"]
		elsif not ENV["TEMP"].nil? then
			@path=ENV["TEMP"]
		elsif File.writable?("/tmp") then
			@path="/tmp"
		elsif File.writable?(".") then
			@path="."
		else
			raise("no writable temporal directory found")
		end

		@pid  = $$.to_s
		@oid  = self.object_id

		@seq = 0 # オブジェクト内通し連番

		# GC呼び出し時にcallする関数を設定する。
		@clean_proc=Mtemp.callback(@path,@pid,@oid)
		ObjectSpace.define_finalizer(self, @clean_proc)

		# ruby終了時にcallする関数を設定する。
		if @gcRM
			at_exit {
				delAllFiles(@path,@pid,@oid)
			}
		end

		return self
	end

	def mkname
		return "#{@path}/__MTEMP_#{@pid}_#{@oid}_#{@seq}"
	end

public

	#== 一時ファイル名の取得
	# 返値: 一時ファイル名(String)
	#
	# 以下のフォーマットで一時ファイル名を生成する。
	# @seqはカウントアップされる。
	# フォーマット: "#{@path}/__MTEMP_#{@pid}_#{@oid}_#{@seq}"
	# nameが指定されれば(@path以外に)GCで削除しなくなる。
	def file(name=nil)
		# ファイル名の生成
		n=nil
		if name==nil then
			n="#{mkname}"
			@seq += 1
		else
			n=name
		end
		return n
	end

	#== 一時ファイル名(名前付きパイプ)の取得
	# 返値: 一時ファイル名(String)
	#
	# 以下のフォーマットで名前付きパイプの一時ファイル名を生成する。
	# @seqはカウントアップされる。
	# フォーマット: "#{@path}/__MTEMP_#{@pid}_#{@oid}_#{@seq}"
	# nameが指定されれば(@path以外に)GCで削除しなくなる。
	def pipe(name=nil)
		# ファイル名の生成
		n=nil
		if name==nil then
			n="#{mkname}"
			@seq += 1
		else
			n=name
		end

		# fifoファイル(名前付きパイプ)の作成
		system "mkfifo #{n}"

		return n
	end

	#== 一時ファイルの出力パスの取得
	# 返値: 一時ファイルを出力パス名(String)
	def path
		return @path
	end

 	#=== 一時ファイルの削除
 	# 以下のコマンドを実行することで一時ファイルを全て削除する。
	# system "rm -rf #{path}/__MTEMP_#{@pid}_#{@oid}_*"
	def rm
		delAllFiles(@path,@pid,@oid)
	end

	# ワークファイル強制削除#{path}
	def forceDel(save=false)
		Dir["#{@path}/__MTEMP_*"].each{|fn|
			if save then
				system("tar cvfzP #{fn}.tar.gz #{fn}")
			end
			system "rm -rf #{fn}"
		}
	end



end # class
end # module

#==============================================      
#以下、サンプルコード(require時は実行されない)       
#==============================================      
if __FILE__ == $0
	tmp=MCMD::Mtemp.new
	fName1=tmp.file
	fName2=tmp.file
	fName3=tmp.file("./xxa")
	puts fName1
	puts fName2
	puts fName3
	File.open(fName1,"w"){|fp| fp.puts "temp1"}
	File.open(fName2,"w"){|fp| fp.puts "temp2"}
	File.open(fName3,"w"){|fp| fp.puts "temp3"}

	tmp=MCMD::Mtemp.new(".")
	fName=tmp.file
	File.open(fName,"w"){|fp| fp.puts "temp"}

	tmp=MCMD::Mtemp.new
	pName=tmp.pipe
	system("ls -l #{pName}")
	system("echo 'abc' > #{pName} &")
	system("cat <#{pName} &")

end # サンプルコード
#==============================================

