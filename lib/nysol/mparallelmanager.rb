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
require "nysol/msysteminfo"
module MCMD

	class MpcManager 
		def initialize(fn="/etc/pclist")
			@localIP = MCMD::SysInfo.getMyIP
			@pcIP  = []
			@pcUID = []
			@pcPWD = []
			@ip2No  = {}
			File.open(fn){|fp|
				while lin = fp.gets do
					next if lin =~ /^#/
					lins = lin.chomp.split
					@pcIP  << lins[1]
					@pcUID << lins[0]
					@pcPWD << lins[2]
					@ip2No[lins[1]] = @pcIP.size-1
				end
			}
		end
		def each
			(0...@pcIP.size).each{|i|
				yield @pcIP[i],@pcUID[i],@pcPWD[i]
			}
		end


		def pcCount 
			return @pcIP.size
		end
		def getIP(no) 
			return @pcIP[no]
		end
		def getUID(no) 
			return @pcUID[no]
		end
		def getPWD(no) 
			return @pcPWD[no]
		end
		def has_IP?(ip)
			return @ip2No.has_key?(ip)
		end

		def getUIDbyIP(ip) 
			return nil unless @ip2No.has_key?(ip)
			return getUID(@ip2No[ip]) 
		end
		def getPWDbyIP(ip) 
			return nil unless @ip2No.has_key?(ip)
			return getPWD(@ip2No[ip]) 
		end


		attr_reader :localIP


	end


	class MparallelManager

		def initialize(mp=4,tim=-1)
			@mp = mp 					# パラレルサイズ
			@thInterval = tim # チェック間隔
			@runpid = {} 			# pid => laneNo ## 動いてるPROCESS
			@slppid = []			# [ [pid ,laneNo child pid] ... ## 休止中PROCESS
			@mtx =  Mutex.new if @thInterval > 0
			@LaneQue = Array.new(mp){|i| i }	
		end

		def emptyLQ?
			@LaneQue.empty?
		end

		# プロセス終了確認
		def waitLane
			finLane =[]
			loop{
				begin 
					rpid = nil
					sts  = nil 
					loop{
						@runpid.each{|k,v|
							rpid ,sts = Process.waitpid2(k,Process::WNOHANG)
							break unless rpid == nil
						}
						break unless rpid == nil
					}
				rescue 
					if @mtx then 
						@mtx.synchronize {
							@runpid.each{|k,v| 
								finLane.push(v)
								@LaneQue.push(v) 
							}
							@runpid.clear
						}
					else
						@runpid.each{|k,v| 
							finLane.push(v)
							@LaneQue.push(v) 
						}
						@runpid.clear
					end
					break
				end
				new_pno = nil
				if @mtx then 
					@mtx.synchronize {
						new_pno = @runpid.delete(rpid)
					}
				else
						new_pno = @runpid.delete(rpid)
				end
				if new_pno != nil then
					finLane.push(new_pno)
					@LaneQue.push(new_pno)
					break
				end
			}
			return finLane
		end

		# 全プロセス終了確認
		def waitall
			rtn = []
			while !@runpid.empty? or !@slppid.empty? do
				rtn.concat(waitLane) 
			end
			return rtn
		end

		# 空き実行レーン取得
		def getLane(wait=true)
			waitLane if wait and @LaneQue.empty? 
			return @LaneQue.shift
		end

		# 実行PID=>lane登録
		def addPid(pid,lane)
			if @mtx then
				@mtx.synchronize { @runpid[pid]=lane }
			else
				@runpid[pid]=lane
			end
		end

		## メモリ,CPUチェッカー
		def runStateCheker 
			return unless @mtx 
			Thread.new {
			begin
			loop{ 
				if MCMD::SysInfo.LimitOver_Mem_Cpu? then
					@mtx.synchronize {
					if @runpid.size > 1 then
						pid = @runpid.keys[0]
					  plist = MCMD::SysInfo.cPIDs(pid)
						stopL = []
				  	plist.reverse_each{|px|
				  		begin
								Process.kill(:STOP, px) 
								stopL << px
							rescue => msg #STOP できなくてもスルー
							  puts "already finish #{px}"
								next
							end
						}
						unless stopL.empty? then
							pno = @runpid.delete(pid)
							@slppid << [pid,pno,stopL] 
						end
					else
						unless @slppid.empty? then
							pid,pno,plist = @slppid.shift
							plist.each{|px|
						  	begin
									Process.kill(:CONT, px) 
								rescue => msg
								  puts "already finish #{px}"
								end
							}
							@runpid[pid]=pno
						end
					end
					}
				else
					@mtx.synchronize {
					unless @slppid.empty? then
						pid,pno,plist = @slppid.shift
						plist.each{|px|
					  	begin
								Process.kill(:CONT, px) 
							rescue => msg
							  puts "already finish #{px}"
							end
						}
						@runpid[pid]=pno
					end
					}
				end
				sleep @thInterval
			}
			rescue => msg 
				p msg
				exit
			end
			}		
		end
	end

	class MparallelManagerByFile < MparallelManager
		def initialize(mp=16,wrk="./",tim=-1)
			super(mp,tim)
			@wrk =wrk 
		end
		
		
		# ファイルでプロセス終了確認
		def waitLane
			finLane =[]
			loop{
				bFlg = false
				# @runpid [No->lane]]
				@runpid.each{|k,v|
					next unless File.exist?("#{@wrk}/#{v}.log")
					jmpF =false
					File.open("#{@wrk}/#{v}.log"){|fp|
						lin=fp.gets
						if lin == nil then
							MCMD::msgLog("UNMATCH FORMAT LOG #{@wrk}/#{v}.log")
							jmpF = true
						elsif lin.split[1].to_i != k then
							MCMD::msgLog("UNMATCH NUMBER #{@wrk}/#{v}.log #{k}")
							jmpF = true
						end
					}
					next if jmpF
					finLane.push(v)
					@LaneQue.push(v)
					if @runpid.delete(k) == nil then
						MCMD::msgLog("NIL FIND NIL FIND")
					end
					File.unlink("#{@wrk}/#{v}.log")
					bFlg = true
				}
				break if bFlg
			}
			return finLane		
		end
		
		def addNo (no,lane)
			if @mtx then
				@mtx.synchronize { @runpid[no]=lane }
			else
				@runpid[no]=lane
			end
		end
		
		
		# 空き実行レーン取得
		def getLane(wait=true)
			waitLane if wait and @LaneQue.empty? 
			return @LaneQue.shift
		end

		## メモリ,CPUチェッカー
		def runStateCheker 
			#何もしない
		end

		def waitall
			rtn = []
			while !@runpid.empty? or !@slppid.empty? do
				rtn.concat(waitLane) 
			end
			return rtn
		end
	end
end
