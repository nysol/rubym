#!/usr/bin/env ruby
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

require "rubygems"
require "nysol/mcsvin"

#= コマンドライン引数の型チェックと設定を扱うクラス
#
# コマンドライン引数は"key=value"、"-key"のいずれかの形式を想定している。
# Unix系OSの引数の標準形式とは異なることに注意する。
#
# チェック内容:
#   1. 指定可能な引数を指定し、それ以外の引数がコマンドラインで指定されればエラー終了(エラーをraise)する。
#   2. 必須の引数を指定し、コマンドラインで指定されていなければエラー終了させる。
#   3. 引数の型を設定し、型に応じた値チェック及び変換をおこなう。
#
# 扱える型:
#   rubyの原始型として:
#      1.str: rubyのString型に変換: デフォルト値の指定 
#      2.int: rubyのFixnum型に変換: デフォルト値の指定、有効な範囲チェック
#      3.float: rubyのFloat型に変換: デフォルト値の指定、有効な範囲チェック
#      4.bool: rubyのtrue/falseに変換: -key タイプのオプションが指定されたかどうかの真偽判定
#   特殊な型として:
#      5.file: rubyのString型に変換: ファイルのreadable or writableチェック
#
#=== 例1
# コマンドライン
# ------------------------------------------------------
# $ ruby test.rb v=0.2 -w
# ------------------------------------------------------
#
# test.rbの内容
# ------------------------------------------------------
# require 'nysol/mcmd'
# include MCMD
#
# args=Margs.new(ARGV)
# val  = args.float("v=") # -> 0.2
# flag = args.bool("-w") # -> true
# ------------------------------------------------------
#
#=== 例2 引数存在チェックや型チェックの例
# コマンドライン
# ------------------------------------------------------
# $ ruby test.rb i=dat.csv v=value -abc
	# ------------------------------------------------------
#
# test.rbの内容
# ------------------------------------------------------
# require 'nysol/mcmd'
# include MCMD
#
# # "i=,o=,w=,-flag,-x"以外の引数が指定されればエラー終了する。
# # "i=,w="引数を指定しなければエラー終了する。
# args=Margs.new(ARGV, "i=,o=,w=,-flag,-x", "i=,w=")
# iFileName = args.file("i=") # -> "dat.csv"
# oFileName = args.str("o=","result.csv") # -> "result.csv"
# weight    = args.float("w=",0.1,0.0,1.0) # -> 0.1
# flag      = args.bool("-abc") # -> true
# wFlag     = args.bool("-w") # -> false
# ------------------------------------------------------
class Margs
	attr_reader :argv
	attr_reader :keyValue

	#== コンストラクタ
	# argv: rubyのARGV変数
	#
	# allKeyWords: key=もしくは-keyによる引数キーワードリスト(String Array)
	#   ここで指定した以外の引数がARGVに指定されていないことをチェックし、指定されていればエラー終了する。
	#   keyListを省略した場合はこのチェックをしない。
	#
	# mandatoryKeyWords: key=による引数キーワードリスト(String Array)
	#   ここで指定した引数がコマンドラインで指定されていなければエラー終了する。
	#   mandatoryKeyWordsを省略した場合はこのチェックをしない。
	def initialize(argv, allKeyWords=nil, mandatoryKeyWords=nil, help_func=nil,ver_func=nil)
		@argv=argv
		@allKeyWords=allKeyWords
		@mandatoryKeyWords=mandatoryKeyWords
		@keyValue=Hash.new
		@cmdName=$0.dup

		# コマンドラインで指定された引数を一旦全てHashに格納する。
		@argv.each{|arg|
			if arg[0..0]=="-" then
				@keyValue[arg]=true
  			begin
					if arg=="--help"
						if help_func
							help_func()
							exit()
						else
							help()
							exit()
						end
					elsif arg=="--version"
						if ver_func
							ver_func()
							exit()
						else
							ver_func()
							exit()
						end
					end
				rescue => err
					# help関数がなければ通過させる。
					break
				end

			else
				pos=arg.index("=")
				if pos==nil then
					raise "invalid argument: `#{arg}'"
				end
				val=arg.split("=",2)[1] # 20140924 by ham
				val="" if val==nil
				@keyValue[arg[0..pos]]=val
			end
		}

		# allKeyWordsのオプションタイプのキーワードを登録する
		if @allKeyWords!=nil then
			@allKeyWords.split(",").each{|kw|
				if kw[0..0]=="-" and @keyValue[kw]==nil then
					@keyValue[kw]=false
				end
			}
		end

		# 指定のキーワード以外のキーワードが指定されていないかチェック
		if @allKeyWords!=nil then
			kwList=@allKeyWords.split(",")
			@keyValue.each{|kw,val|
				if kwList.index(kw)==nil then
					raise "I don't know such a argument: `#{kw}'"
				end
			}
		end

		# 必須引数のチェック
		if @mandatoryKeyWords !=nil then
			@mandatoryKeyWords.split(",").each{|kw|
				if @keyValue[kw]==nil and kw[0..0]!="-" then
					raise "argument `#{kw}' is mandatory"
				end
			}
		end
	end

public
	#== String型引数の値のチェックと取得
	# 返値: 引数で指定された値(String)
	#
	# key: "key="形式の引数キーワード(String)
	#   ここで指定した引数の値をStringとして返す。
	#   コマンドラインで指定されていなければdefaultの値を返す。
	#
	# default: コマンドラインで指定されなかったときのデフォルト値(String)
	def str(key,default=nil,token1=nil,token2=nil)
		val=@keyValue[key]
		val=default if val==nil
		if val!=nil then
			if token1!=nil then
				val=val.split(token1)
				if token2!=nil then
					ary=val.dup()
					val=[]
					ary.each{|v|
						val << v.split(token2)
					}
				end
			end
		end
		return val
	end

	#== Fixnum型引数の値のチェックと取得
	# 返値: 引数で指定された値(Fixnum)
	#
	# key: "key="形式の引数キーワード
	#   ここで指定した引数の値をFloatとして返す。
	#   コマンドラインで指定されていなければdefaultの値を返す。
	#
	# default: コマンドラインで指定されなかったときのデフォルト値
	#
	# from: 値の下限値。指定した値が下限値を下回ればエラー終了する。
	#
	# to: 値の上限値。指定した値が上限値を上回ればエラー終了する。
	def int(key, default=nil, from=nil, to=nil)
		val=@keyValue[key]
		val=default if val==nil
		
		if val!=nil then
			val=val.to_i
			if from != nil and val<from then
				raise "range error: `#{key}=#{val}': must be in [#{from}..#{to}]"
			end
			if to   != nil and val>to   then
				raise "range error: `#{key}=#{val}': must be in [#{from}..#{to}]"
			end
		end

		return val
	end

	#== Float型引数の値のチェックと取得
	# 返値: 引数で指定された値(Float)
	#
	# key: "key="形式の引数キーワード
	#   ここで指定した引数の値をFloatとして返す。
	#   コマンドラインで指定されていなければdefaultの値を返す。
	#
	# default: コマンドラインで指定されなかったときのデフォルト値
	#
	# from: 値の下限値。指定した値が下限値を下回ればエラー終了する。
	#
	# to: 値の上限値。指定した値が上限値を上回ればエラー終了する。
	def float(key, default=nil, from=nil, to=nil)
		val=@keyValue[key]
		val=default if val==nil
		
		if val!=nil then
			val=val.to_f
			if from != nil and val<from then
				raise "range error: `#{key}=#{val}': must be in [#{from}..#{to}]"
			end
			if to   != nil and val>to   then
				raise "range error: `#{key}=#{val}': must be in [#{from}..#{to}]"
			end
		end

		return val
	end

	#== Bool型引数の値のチェックと取得
	# 返値: 引数で指定されたかどうか(true/false)
	#
	# key: "-key"形式の引数キーワード
	#   ここで指定した引数がコマンドラインで指定されていればtrueを、指定されていなければfalseを返す。
	def bool(key)
		return @keyValue[key]
	end

	#== ファイル型引数の値のチェックと取得
	# 返値: 引数で指定されたファイル名(String)
	#
	# key: "key="形式の引数キーワード
	#   ここで指定した引数の値をファイル名と想定し、そのファイルがreadable(writable)かどうかをチェックする。
	#   readable(writable)であればそのファイル名を返し、readable(writable)でなければエラー終了する。
	#   readable(writable)チェックをしないのであればMargs::strを使えばよい。
	#
	# mode: "r"もしくは"w"を指定し、rならばreadableチェックを、wならwritebleチェックを行う。
	def file(key,mode="r",default=nil)
		val=@keyValue[key]
		val=default if val==nil

		if val!=nil then # valがnilの場合(ex. 値なし指定"i=")はノーチェックで通す
			if mode=="r" then
				if not File.readable? val then
					raise "file open error: `#{val}' is not readable"
				end
			elsif mode=="w" then
				if not File.writable? File.dirname(val) then
					raise "file open error: `#{val}' is not writable"
				end
			end
		end
		return val
	end

	#== Field型引数の値のチェックと取得
	# 返値: 各種配列のHash
	# 	key=a1:b1%c1,a2:b2%c2,...
	#   names: [a1,a2,...]
	#   newNames: [b1,b2,...]
	#   flags:  [c1,c2,...]
	#   fld2csv: a1,a2,...のCSVファイルにおける項目番号(0から始まる)
	#   csv2fld: CSVファイルの項目番号に対するa1,a2,...の番号(0から始まる)
	def field(key,iFile,default=nil,min=nil,max=nil)
		return unless iFile
		val=@keyValue[key]
		val=default if val==nil

		names1=[]
		names2=[]
		flags=[]
		fld2csv=[]
		csv2fld=[]

		# names1,names2,flagsの設定
		if val!=nil then
			val1=val.split(",")
			val1.each{|v|
				val2=v.split("%")
				val3=val2[0].split(":")
				names1 << val3[0]
				names2 << val3[1]
				flags  << val2[1]
			}

			if min then
				raise "#{key} takes at least #{min} field name(s)" if names1.size<min
			end
			if max then
				raise "#{key} takes at most #{max} field name(s)" if names1.size>max
			end

			iNames=MCMD::Mcsvin.new("i=#{iFile}").names
			# fld2csvの設定
			(0...names1.size).each{|i|
				pos=iNames.index(names1[i])
				if pos==nil then
					raise "field name not found: `#{names1[i]}'"
				end
				fld2csv << pos
			}

			# csv2fldの設定
			(0...iNames.size).each{|i|
				pos=fld2csv.index(i)
				if pos!=nil
					csv2fld << pos
				else
					csv2fld << nil
				end
			}

			ret=Hash.new
			ret["names"]=names1
			ret["newNames"]=names2
			ret["flags"]=flags
			ret["fld2csv"]=fld2csv
			ret["csv2fld"]=csv2fld
			ret["csvNames"]=iNames
			return ret
		else
			return nil
		end
	end

	# key-valuを配列で返す
	def getKeyValue(prefix=nil)
		ret=[]
		@keyValue.each{|k,v|
			ret << ["#{prefix}#{k}","#{v}"]
		}
		return ret
	end

	# コマンドラインをkey-valuを配列で返す
	def cmdline()
  	return "#{@cmdName} #{@argv.join(' ')}"
	end

end # class
end # module

#==============================================
#以下、サンプルコード(require時は実行されない)
#==============================================
if __FILE__ == $0
	include MCMD

	# $ ruby ./margs.rb i=dat.csv v=value -abc
	#args=Margs.new(ARGV, "i=,o=,w=,v=,-flag,-x,-abc", "i=,w=")
	args=Margs.new(ARGV, "f=")
	fld=args.field("f=","xxa")
exit
	p fld["names"]
	p fld["newNames"]
	p fld["flags"]
	p fld["fld2csv"]
	p fld["csv2fld"]
exit
	#p args.str("f=",",",":")
	iFileName = args.file("i=") # -> "dat.csv"
	oFileName = args.str("o=","result.csv") # -> "result.csv"
	weight    = args.float("w=",0.1,0.0,1.0) # -> 0.1
	flag      = args.bool("-abc") # -> true
	wFlag     = args.bool("-w") # -> false

end # サンプルコード
#==============================================
