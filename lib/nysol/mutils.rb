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
#= MCMD ruby拡張ライブラリ
# ユーティリティツール
# Array.
#   maddPrefix
#   maddSuffix
#   mslidepair
# MCMD::
#		errorLog(msg="")
#		warningLog(msg="")
#		endLog(msg="")
#		msgLog(msg="",time=true,header=true)
#		mkDir(path,rm=false)
#		chkCmdExe(cmd,type,arg1=nil)
#		chkRexe(libs)
#		mcat(fName,oFile)

class Array

	def maddPrefix(strs)
		strs = [strs] if strs.class != Array
		rtn =[]
		params=self.dup
		params.each{|v|
			strs.each{|str| rtn << "#{str}#{v}" }
		}
		return rtn	
	end

	def maddSuffix(strs)
		strs = [strs] if strs.class != Array
		rtn =[]
		params=self.dup
		params.each{|v|
			strs.each{|str| rtn << "#{v}#{str}" }
		}
		return rtn	
	end

	def mslidepair
		rtn =[]
		params=self.dup
		(1...params.size).each{|i|
			rtn << [params[i-1],params[i]]	
		}
		return rtn	
	end
end


module MCMD
	
	def MCMD::errorLog(msg="")
		vbl=ENV["KG_ScpVerboseLevel"]
		if(not vbl or vbl.to_i>=1) then
			STDERR.puts "#ERROR# #{msg}; #{Time.now.strftime('%Y/%m/%d %H:%M:%S')}"
		end
	end

	def MCMD::warningLog(msg="")
		vbl=ENV["KG_ScpVerboseLevel"]
		if(not vbl or vbl.to_i>=2) then
			STDERR.puts "#WARNING# #{msg}; #{Time.now.strftime('%Y/%m/%d %H:%M:%S')}"
		end
	end

	def MCMD::endLog(msg="")
		vbl=ENV["KG_ScpVerboseLevel"]
		if(not vbl or vbl.to_i>=3) then
			STDERR.puts "#END# #{msg}; #{Time.now.strftime('%Y/%m/%d %H:%M:%S')}"
		end
	end

	def MCMD::msgLog(msg="",time=true,header=true)
		vbl=ENV["KG_ScpVerboseLevel"]
		if(not vbl or vbl.to_i>=4) then
			str=""
			str << "#MSG# " if header
			str << msg
			str << "; #{Time.now.strftime('%Y/%m/%d %H:%M:%S')}" if time
			STDERR.puts str
		end
	end

	# ディレクトリの作成
	def MCMD::mkDir(path,rm=false)
		if File.exist?(path)
			if rm
				FileUtils.rm_rf(path) if rm
				FileUtils.mkdir_p(path)
			end
		else
			FileUtils.mkdir_p(path)
		end
	end

	# コマンド実行チェック
	# 実行可能ならtrue else false
	def MCMD::chkCmdExe(cmd,type,arg1=nil)
		ret=true
		if(type=="executable")
			system "#{cmd} 2>/dev/null"
			if($?.exitstatus==127)
				MCMD::errorLog("command not found (type=#{type}): '#{cmd}'.")
				ret=false
			end
		elsif(type=="wc")
			log=`#{cmd} #{type} 2>&1`
			if log.chomp.size()<arg1
  			MCMD::errorLog("command not found (type=#{type}): '#{cmd}'.")
				ret=false
			end
		else
			log=`#{cmd} #{type} 2>&1`
			if log.chomp!=arg1
  			MCMD::errorLog("command version mismatch: '#{cmd}': needs '#{arg1}', but '#{log}.")
				ret=false
			end
		end

		return ret
	end

	# rの実行チェックとr ライブラリのインストールチェック
	def MCMD::chkRexe(libs)
		log=`R --version 2>&1`
		if log.chomp.size()<100
			MCMD::errorLog("R is not installed.")
			return false
		end

		libStr=""
		libs.split(",").each{|lib|
			libStr << "p=packageVersion(\"#{lib}\")\n"
		}

		wf=MCMD::Mtemp.new
		xxscp=wf.file
		File.open(xxscp,"w"){|fpw|
			fpw.puts <<EOF
			tryCatch({
				#{libStr}
			},
			error=function(e){
  			message(e)
				quit(save="no", status=1)
			})
			quit(save="no", status=0)
EOF
		}				

		# it will be aborted here if the library is not found
		ret=system "R -q --vanilla --slave --no-save --no-restore < #{xxscp}"
		unless ret
			puts "\n"
			MCMD::errorLog("R package shown above is not installed.")
		end

		# return true if nothing happened
		return ret
	end

	# mcat i=のファイル名文字列がbashの位置行文字数制限(たぶん1024くらい？)に引っかかるのを回避するmcat
	# date,noが指定されれば、date,no以前のデータをmcatし、oFileに出力する。
	# マッチしたファイル名配列を返す。
	def MCMD::mcat(fName,oFile)
		files=[]
		if fName.class.name=="Array"
			fName.each{|name|
				files.concat(Dir["#{name}"])
			}
		else
			files=Dir["#{fName}"]
		end

		wf=MCMD::Mtemp.new
		xxbase=wf.file
		xxbaseX=wf.file

		split=20
		collect_path =[]
		(0...files.size).each{|i|
			if i==0
				system("cp #{files[0]} #{xxbase}")
				next
			end
			collect_path << "#{files[i]}"
			if i%split == 0 or i==files.size-1 then
				system("mcat i=#{xxbase},#{collect_path.join(",")} -skip_fnf o=#{xxbaseX}")
				system("cp #{xxbaseX} #{xxbase}")
				collect_path = []
			end
		}
		system("cp #{xxbase} #{oFile}") if files.size>0

		return files
	end


end
