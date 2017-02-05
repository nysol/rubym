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
require 'rubygems' 
require 'set'


#==========================================================
# vm_stat output
#==========================================================
# Mach Virtual Memory Statistics: (page size of 4096 bytes)
# Pages free:                              640719.
# Pages active:                            550274.
# Pages inactive:                          246385.
# Pages speculative:                       140973.
# Pages throttled:                              0.
# Pages wired down:                        518097.
# Pages purgeable:                          32227.
# "Translation faults":                   5375781.
# Pages copy-on-write:                     220656.
# Pages zero filled:                      3602918.
# Pages reactivated:                            2.
# Pages purged:                                 0.
# File-backed pages:                       350402.
# Anonymous pages:                         587230.
# Pages stored in compressor:                   0.
# Pages occupied by compressor:                 0.
# Decompressions:                               0.
# Compressions:                                 0.
# Pageins:                                 138994.
# Pageouts:                                     0.
# Swapins:                                      0.
# Swapouts:                                     0.
#==========================================================
# Pages freeの行をメモリ空きとする
#==========================================================
module MCMD
	
	
	
	module SysInfo
		def self.ostype
			if RUBY_PLATFORM.match(/darwin/) then
				return "Darwin"
			else
				return "Linux"
			end
			return nil
		end
		
		#mac用トータルメモリ情報取得
		def self.ttlMemoryOnOSX
			return `sysctl hw.memsize`.split[-1]
		end
		def self.rstMemoryOnOSX	
			rmem = `vm_stat | grep "^Pages free"`.gsub(/\.$/,"").split[-1]
			rmem = rmem.to_f * 4096 if rmem != nil 
			return rmem
		end

		#mac用トータルメモリ情報取得
		def self.ttlRstMemoryOnLinux
			memi = `free | grep "^Mem"`.split
			return memi[1],memi[3]
		end

		def self.memoryInfoOnOSX 
			return ttlMemoryOnOSX,rstMemoryOnOSX
		end

		def self.memoryInfoOnLinux
			return ttlRstMemoryOnLinux
		end

		def self.getMemoryInfo
			if ostype == "Darwin" then
				return memoryInfoOnOSX 
			else
				return memoryInfoOnLinux 
			end
		end

		def self.restMemoryRate
			ttlmem,rstmem = getMemoryInfo
			if ttlmem != nil and rstmem != nil then
				return rstmem.to_f * 100.0 / ttlmem.to_f
			end
			return nil
		end	

		#=======================================================
		def self.idleCPUOnOSX(priod=1)
			# sar output
			# 11:05:15  %usr  %nice   %sys   %idle
			# 11:05:16    2      0      1     96
			# Average:      2      0      1     96   
			sar_sp = `sar -u #{priod} 1 | grep ^Average`.split
			return sar_sp[4].to_f
		end
		
		def self.idleCPUOnLinux(priod=1)
			#		procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
			# r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
			# 4  0      0 591720  98804 699532    0    0    71    13   46  855  9  0 91  0  0
			# 0  0      0 591712  98804 699532    0    0     0     0   40  739  6  2 92  0  0
			vstat_sp = `vmstat #{priod} 2 | tail -n 1 `.split
			return vstat_sp[-3].to_f
		end
		
		def self.idleCPU
			if ostype == "Darwin" then
				return idleCPUOnOSX 
			else
				return idleCPUOnLinux 
			end
		end

		def self.usedMemorybyPID
			rtn = []
			`ps -p #{pid} -o pid,%cpu,%mem,vsz,rss,time`.split("\n").each{|lstr|
				vals = lstr.split("\s")
				next if vals[0] == "PID"
				rtn << vals[4].to_f * 0.001
				tm = vals[5].split(":")
				rtn << tm[0].to_i * 60 + tm[1].to_f
			}
			return rtn
		end
		
		def self.LimitOver_Mem_Cpu?(limM=5,limC=5)
			memR = restMemoryRate
			cpuR = idleCPU
			return  ( memR != nil and cpuR != nil and ( memR < limM or cpuR < limC ) )


		end
		
		#=======================================================
		def self.cPIDsOnOSX(pid)
			rls =[pid]
			pids =[pid]
			loop {
				rtn =[]
				pidset = Set.new(pids)
				`ps o pid,ppid | grep "#{pids.join("\|")}"`.split("\n").each{|lstr|
					vals = lstr.split("\s")
					ppid = vals[1].to_i
					if pidset.include?(ppid) then
						rtn << vals[0].to_i
					end
				}
				rls.concat(rtn)
				pids = rtn
				break if pids.empty? 
			}
			return rls
		end
		def self.cPIDsOnLinux(pid)
			rls =[pid]
			return rls
		end

		def self.cPIDs(pid)
			if ostype == "Darwin" then
				return cPIDsOnOSX(pid)
			else
				return cPIDsOnOSX(pid)
			end
		end

		#=======================================================
		def self.getMyIPOnOSX
			`ifconfig en0 | grep "inet "`.split[1]
		end
		def self.getMyIPOnLinux
			rls = `ifconfig eth0 | grep "inet "`.split[1]
			rls.gsub!(/addr:/,"") if rls
			return rls 
		end
		
		
		def self.getMyIP
			if ostype == "Darwin" then
				return getMyIPOnOSX
			else
				return getMyIPOnLinux
			end
			
		end
	end
end


if __FILE__ == $0 then
p MCMD::SysInfo.ostype
p MCMD::SysInfo.restMemoryRate
p MCMD::SysInfo.idleCPU
p MCMD::SysInfo.cPIDs(75932)
end
