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
require "nysol/mtemp"
require "nysol/mnettools"
require "nysol/mrubyparse"
require "nysol/mparallelmanager"
$FtpUSE=true

class Array

	# データ収集
  # fn 集めるファイル名 out 出力先　nFlg：項目名無しFLG
	# outの最後が"/"でない場合は１ファイルと見なす
	# 配列にはデータがあるip,pathとが含まれている
	# [ [ip1,path1],[ip2,path2] ...,[ipn,pathn]]
	# データ量によっては端末ごとにcat＆圧縮した方が高速化できるかも
	def mcollect(fn,out,nFlg=false,pclist="/etc/pclist")
		fn = [fn] if fn.class != Array 
		out = [out] if out.class != Array 
		raise "no match size in-out " if fn.size != out.size 

		temp=MCMD::Mtemp.new
		params=self.dup

		# PC_LIST読み込み
		pcM = MCMD::MpcManager.new(pclist)

		# ip毎に配列集約 
		dlist ={}
		params.each{|ip,path|
			raise "unknown ip " unless pcM.has_IP?(ip) 
			dlist[ip] = [] unless dlist.has_key?(ip)
			dlist[ip] << path
		}
		
		(0...fn.size).each{|i|
			type = out[i] =~ /\/\s*$/ ?  0 : 2
			type += 1 if dlist.size != 0

			#パラメータセット
			nfr  = "/#{fn[i]}"
			nrev = out[i]
			lcin = fn[i]
			to   = out[i] 
			if type == 3 then
				nrev = "#{temp.file}/" 
				lcin = "#{nrev}*"
			end

			# collet 
			dlist.each{|ip,path|
					MCMD::NetTools.recv(ip,pcM.getUIDbyIP(ip),path.maddSuffix(nfr),nrev,pcM.getPWDbyIP(ip))
			}
			case type
			when 0 #出力ディレクトリ(local)
				MCMD::mkDir(to,true)
				system "cp #{lcin} #{to}"
			when 2,3 #出力ファイル	(local)
				if nFlg then
					system "mcat i=#{lcin} o=#{to} -nfn"
				else
					system "mcat i=#{lcin} o=#{to}"
				end			
			end
		}
	end

	# 並列処理each
	def meach(mpCount=4,msgcnt=100,tF=false,&block)
		tim = tF ? 5 : -1
		params=self.dup
		ttl    = params.size
		nowcnt = 0 
		mpm = MCMD::MparallelManager.new(mpCount,tim)
		mpm.runStateCheker

		while params.size>0
			param=params.delete_at(0) 
			nowlane = mpm.getLane
			# blockの実行
			pid=fork {
				case block.arity
				when 1
					yield(param)
				when 2
					yield(param,nowcnt)				
				when 3
					yield(param,nowcnt,nowlane)				
				else
					raise "unmatch args size."
				end
			}
			nowcnt+=1
			MCMD::msgLog("meach start #{param} (#{nowcnt}/#{ttl})") if msgcnt!=0 and nowcnt%msgcnt == 0
			mpm.addPid(pid,nowlane) 
		end
		mpm.waitall
		return []
	end
	
	def meachc(mpInfo=[4,4],msgcnt=100,pclist="/etc/pclist",bg=true,&block)
		# -----------------------------------------------------
		# pc情報設定 & 並列数決定
		# -----------------------------------------------------
		pcM = MCMD::MpcManager.new(pclist)
		mpPC = mpLim = 4
		if mpInfo.class == Array then
			mpPC  = mpInfo[0] if mpInfo[0] 
			mpLim = mpInfo[1] if mpInfo[1] 
		else
			mpPC  = mpInfo
		end
		mpPC  = pcM.pcCount  if mpPC > pcM.pcCount
		mpMax = mpPC * mpLim

		# -----------------------------------------------------
		# 呼び出し元ファイル ＆ ローカル変数取得
		# -----------------------------------------------------
		fn ,lin = block.source_location 
		value = block.binding.eval("local_variables") 
		valueV=[]
		value.each{|v|
			clsinfo = block.binding.eval("#{v}.class")
			case clsinfo.to_s
			when "String"
				valinfo = block.binding.eval("#{v}")
				valueV << "#{v} = \"#{valinfo}\""
			when "Fixnum","Bignum","Float"
				valinfo = block.binding.eval("#{v}")
				valueV << "#{v} = #{valinfo}"
			when "Array"
				valinfo = block.binding.eval("#{v}")
				valueV << "#{v} = #{valinfo}"
			end 
		}

		# -----------------------------------------------------
		# 並列用プログラム生成
		# -----------------------------------------------------
		tempC=MCMD::Mtemp.new
		runspf=tempC.file
		MCMD::MrubyParse.new(fn,lin,"meachc",valueV).output(runspf)		

		# -----------------------------------------------------
		# 作業ディレクトリ決定
		# -----------------------------------------------------
		local_WkD = tempC.file
		net_WkD   = tempC.file
		MCMD::mkDir(local_WkD)

		# -----------------------------------------------------
		# 並列処理
		# -----------------------------------------------------
		params=self.dup
		mpm = MCMD::MparallelManagerByFile.new(mpMax,local_WkD)
		ttl    = params.size
		nowcnt = 0 
		rtnlist =[]

		while params.size>0

			param=params.delete_at(0) 
			nowlane = mpm.getLane

			# blockの実行
			pid=fork {

				stNo = nowlane%mpPC
				param = [param] if param.class != Array
				# -----------------------------------------------------
				# 起動スクリプト生成
				# -----------------------------------------------------
				runinit_Scp = "#{local_WkD}/#{File.basename(runspf)}_#{nowlane}.sh"
				net_nowwkD  = "#{net_WkD}/#{nowcnt}" 
				File.open(runinit_Scp,"w"){|fpw|
					fpw.puts "cd #{net_nowwkD}"
					case block.arity
					when 1
						fpw.puts "ruby #{File.basename(runspf)} #{param.join(",")}" 
					when 2
						fpw.puts "ruby #{File.basename(runspf)} #{param.join(",")} #{nowcnt}" 
					when 3
						fpw.puts "ruby #{File.basename(runspf)} #{param.join(",")} #{nowcnt} #{nowlane}"
					else
						raise "unmatch args size."
					end
					fpw.puts "echo pgmend #{nowcnt} >> #{net_nowwkD}/endlog"
					fpw.puts "ls -lR >> #{net_nowwkD}/endlog"
					fpw.puts "msend.rb i=#{net_nowwkD}/endlog uid=#{pcM.getUID(stNo)} o=#{pcM.localIP}:#{local_WkD}/#{nowlane}.log"
				}			
			
				# -----------------------------------------------------
				# スクリプトファイル&データ転送
				# -----------------------------------------------------
				MCMD::msgLog("meachc snddata #{fn}:#{lin} (#{nowcnt}/#{ttl})") if msgcnt!=0 and nowcnt%msgcnt == 0
				distSrc  = "#{net_nowwkD}/#{File.basename(runspf)}"
				distSrcI = "#{net_nowwkD}/#{File.basename(runspf)}.sh"
				MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),runinit_Scp,distSrcI,pcM.getPWD(stNo))
				MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),runspf     ,distSrc ,pcM.getPWD(stNo))
				param.each{|dt|
					MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),dt,"#{net_nowwkD}/#{dt}",pcM.getPWD(stNo))
				}

				# -----------------------------------------------------
				# プログラム実行
				# -----------------------------------------------------
				MCMD::msgLog("meachc pgmstart #{fn}:#{lin} (#{nowcnt}/#{ttl})") if msgcnt!=0 and nowcnt%msgcnt == 0
				MCMD::NetTools.cmdRun(pcM.getIP(stNo),pcM.getUID(stNo),"nohup bash #{distSrcI} 1> #{net_nowwkD}/RunLog 2>&1 &")
			}
			rtnlist << [ pcM.getIP(nowlane%mpPC),"#{net_WkD}/#{nowcnt}" ]
			mpm.addNo(nowcnt,nowlane) 
			nowcnt+=1
			Process.detach(pid)

		end
		mpm.waitall		
		return rtnlist
	end


	def meachcN(mpInfo=[4,4],msgcnt=100,pclist="/etc/pclist",bg=true,&block)
		# -----------------------------------------------------
		# pc情報設定 & 並列数決定
		# -----------------------------------------------------
		pcM = MCMD::MpcManager.new(pclist)
		mpPC = mpLim = 4
		if mpInfo.class == Array then
			mpPC  = mpInfo[0] if mpInfo[0] 
			mpLim = mpInfo[1] if mpInfo[1] 
		else
			mpPC  = mpInfo
		end
		mpPC  = pcM.pcCount  if mpPC > pcM.pcCount
		mpMax = mpPC * mpLim

		# -----------------------------------------------------
		# 呼び出し元ファイル ＆ ローカル変数取得
		# -----------------------------------------------------
		fn ,lin = block.source_location 
		value = block.binding.eval("local_variables") 
		valueV=[]
		value.each{|v|
			clsinfo = block.binding.eval("#{v}.class")
			case clsinfo.to_s
			when "String"
				valinfo = block.binding.eval("#{v}")
				valueV << "#{v} = \"#{valinfo}\""
			when "Fixnum","Bignum","Float"
				valinfo = block.binding.eval("#{v}")
				valueV << "#{v} = #{valinfo}"
			when "Array"
				valinfo = block.binding.eval("#{v}")
				valueV << "#{v} = #{valinfo}"
			end 
		}

		# -----------------------------------------------------
		# 並列用プログラム生成
		# -----------------------------------------------------
		tempC=MCMD::Mtemp.new
		runspf=tempC.file
		MCMD::MrubyParse.new(fn,lin,"meachcN",valueV).output(runspf)		

		# -----------------------------------------------------
		# 作業ディレクトリ決定
		# -----------------------------------------------------
		local_WkD = tempC.file
		net_WkD   = tempC.file
		net_HMD   = ENV['PWD'].sub(/#{ENV['HOME']}\//,"")
		MCMD::mkDir(local_WkD)

		# -----------------------------------------------------
		# 並列処理
		# -----------------------------------------------------
		params=self.dup
		mpm = MCMD::MparallelManagerByFile.new(mpMax,local_WkD)
		ttl    = params.size
		nowcnt = 0 
		rtnlist =[]

		while params.size>0

			param=params.delete_at(0) 
			nowlane = mpm.getLane

			# blockの実行
			pid=fork {

				stNo = nowlane%mpPC
				param = [param] if param.class != Array
				# -----------------------------------------------------
				# 起動スクリプト生成
				# -----------------------------------------------------
				runinit_Scp = "#{local_WkD}/#{File.basename(runspf)}_#{nowlane}.sh"
				net_nowwkD  = "#{net_WkD}/#{nowcnt}" 
				distSrc  = "#{net_nowwkD}/#{File.basename(runspf)}"
				distSrcI = "#{net_nowwkD}/#{File.basename(runspf)}.sh"


				File.open(runinit_Scp,"w"){|fpw|
					fpw.puts "mkdir -p #{net_HMD}"
					fpw.puts "cd #{net_HMD}"
					case block.arity
					when 1
						fpw.puts "ruby #{distSrc} #{param.join(",")}" 
					when 2
						fpw.puts "ruby #{distSrc} #{param.join(",")} #{nowcnt}" 
					when 3
						fpw.puts "ruby #{distSrc} #{param.join(",")} #{nowcnt} #{nowlane}"
					else
						raise "unmatch args size."
					end
					fpw.puts "echo pgmend #{nowcnt} >> #{net_nowwkD}/endlog"
					fpw.puts "ls -lR >> #{net_nowwkD}/endlog"
					fpw.puts "msend.rb i=#{net_nowwkD}/endlog uid=#{pcM.getUID(stNo)} o=#{pcM.localIP}:#{local_WkD}/#{nowlane}.log"
				}			
			
				# -----------------------------------------------------
				# スクリプトファイル&データ転送
				# -----------------------------------------------------
				MCMD::msgLog("meachcN snddata #{fn}:#{lin} (#{nowcnt}/#{ttl})") if msgcnt!=0 and nowcnt%msgcnt == 0
				MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),runinit_Scp,distSrcI,pcM.getPWD(stNo))
				MCMD::NetTools.send(pcM.getIP(stNo),pcM.getUID(stNo),runspf     ,distSrc ,pcM.getPWD(stNo))

				# -----------------------------------------------------
				# プログラム実行
				# -----------------------------------------------------
				MCMD::msgLog("meachcN pgmstart #{fn}:#{lin} (#{nowcnt}/#{ttl})") if msgcnt!=0 and nowcnt%msgcnt == 0
				MCMD::NetTools.cmdRun(pcM.getIP(stNo),pcM.getUID(stNo),"nohup bash #{distSrcI} 1> #{net_nowwkD}/RunLog 2>&1 &")
			}
			rtnlist << [ pcM.getIP(nowlane%mpPC),"#{net_WkD}/#{nowcnt}" ]
			mpm.addNo(nowcnt,nowlane) 
			nowcnt+=1
			Process.detach(pid)

		end
		mpm.waitall		
		return rtnlist
	end


end
