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
require 'net/ftp'
require "nysol/mtemp"



module MCMD

	module NetTools
		@@ftpUse=true
		@@retry_scp = 5
		if File.exist?("/etc/nysol_netconf") then
			File.open("/etc/nysol_netconf"){|fp|
				while lin = fp.gets do
					sp = lin.chomp!.split()
					if sp[0] == "FtpUse" then
						@@ftpUse=true if sp[1] == "true"
						@@ftpUse=false if sp[1] == "falsed"
					elsif sp[0] == "RetryTimes" then
						@@retry_scp = sp[1].to_i if sp[1]
					end 
				end
			}
		end
	
		def self.config_info
			puts "R #{@@retry_scp} F #{@@ftpUse}"
		end
	
		def self.cmdRun(ip,uid,cmd,secret=nil)
			sts = false
			@@retry_scp.times{|i|
				if secret then
					sts = system("ssh -i #{secret} #{uid}@#{ip} '#{cmd}'")
				else
					sts = system("ssh #{uid}@#{ip} '#{cmd}'")
				end
				break if sts
				sleep 2**i
				MCMD::warningLog("SSH CMDRUN RETRY(#{i+1}/#{@@retry_scp})")		

			}
			MCMD::warningLog("ERROR by SSH ") unless sts			
		end

		# バックグランド実行
		def self.cmdRun_b(ip,uid,cmd,tag="" ,secret=nil)
			sts = false
			if secret then
				sts = system("ssh -i #{secret} #{uid}@#{ip} 'nohup #{cmd}'")
			else
				sts = system("ssh #{uid}@#{ip} 'nohup #{cmd}'")
			end
			MCMD::warningLog("ERROR by SSH(nohub)") unless sts			
		end


		#SCPファイル送信
		def self.scp(ip,uid,from,to,secret=nil)
			sts =false
			unless File.file?(from) then
				raise "File not found."
			end
			if to =~ /\/$/ then
				cmdRun(ip,uid,"mkdir -p #{to}",secret)
			else				
				cmdRun(ip,uid,"mkdir -p #{File.dirname(to)}",secret)
			end	
			if secret then
				@@retry_scp.times{|i|
					sts = system("scp -i #{secret} -C #{from} #{uid}@#{ip}:#{to}")
					break if sts
					sleep 2**i
					MCMD::warningLog("SCP SEND RETRY(#{i+1}/#{@@retry_scp})")		
				}
			else
				@@retry_scp.times{|i|
					sts = system("scp -C #{from} #{uid}@#{ip}:#{to}")
					break if sts
					sleep 2**i
					MCMD::warningLog("SCP SEND RETRY(#{i+1}/#{@@retry_scp})")		
				}
			end
			MCMD::warningLog("send ERROR by scp") unless sts
		end


		#Ftpファイル送信
		def self.ftp(ip,uid,from,to,secret)
			sts =false
			unless File.file?(from) then
				raise "File #{from} not found. "
			end
			if to =~ /\/$/ then
				cmdRun(ip,uid,"mkdir -p #{to}")
			else
				cmdRun(ip,uid,"mkdir -p #{File.dirname(to)}")
			end	
			temp=MCMD::Mtemp.new
			fn = temp.file
			File.open("#{fn}","w"){|fw|
				fw.puts "open #{ip}"
				fw.puts "user #{uid} #{secret}"
				fw.puts "prompt"
				fw.puts "bi"
				fw.puts "put #{from} #{to}"
				fw.puts "bye"
			}

			@@retry_scp.times{
				sts = system("ftp -n < #{fn} > /dev/null")
				#sts = system("ftp -n < #{fn} ")
				break if sts
				sleep 2**i
				MCMD::warningLog("FTP SEND RETRY(#{i+1}/#{@@retry_scp})")		
			}
			MCMD::warningLog("send ERROR by ftp") unless sts
		end

		def self.send(ip,uid,from,to,secret)
			if @@ftpUse then 
				ftp(ip,uid,from,to,secret)
			else
				scp(ip,uid,from,to)			
			end
		end





		#SCPファイル受信
		def self.scp_r(ip,uid,from,to,secret=nil)
			if to =~ /\/$/ then
				system("mkdir -p #{to}")
			else				
				system("mkdir -p #{File.dirname(to)}")
			end	
			from.each{|fn|
				if secret then
					system("scp -i #{secret} -C #{uid}@#{ip}:#{fn} #{to}> /dev/null")
				else
					system("scp -C #{uid}@#{ip}:#{fn} #{to} > /dev/null")
				end
			}
		end

		#ftpファイル受信
		# 
		#MCMD::NetTools.ftp_r(ip,pcinfo[ip][0],path.addSuffix("/#{fn[i]}"),dicName,pcinfo[ip][1])

		def self.ftp_r(ip,uid,from,to,secret)
			tod = to
			if to =~ /\/$/ then
				system("mkdir -p #{to}")
			else				
				system("mkdir -p #{File.dirname(to)}")
				tod = File.dirname(to)
			end	
			temp=MCMD::Mtemp.new
			fn = temp.file
			File.open("#{fn}","w"){|fw|
				fw.puts "open #{ip}"
				fw.puts "user #{uid} #{secret}"
				fw.puts "prompt"
				fw.puts "lcd #{tod}"
				fw.puts "bi"
				from.each{|fr|
					fw.puts "cd #{File.dirname(fr)}"
					fw.puts "mget #{File.basename(fr)}"
				}
				fw.puts "bye"
			}
			@@retry_scp.times{|i|
				sts = system("ftp -n < #{fn} > /dev/null")
				break if sts
				sleep 2**i
				MCMD::warningLog("FTP RECV RETRY(#{i+1}/#{@@retry_scp})")		
			}
		end

		def self.recv(ip,uid,from,to,secret)
			if @@ftpUse then 
				ftp_r(ip,uid,from,to,secret)
			else
				scp_r(ip,uid,from,to)			
			end
		end


	end
end


if __FILE__ == $0 then

MCMD::NetTools.scp("192.168.4.212","nysol","mtemp.rb","/tmp/xxxa")
MCMD::NetTools.cmdRun("192.168.4.212","nysol","cd /tmp; ls -l xxxa")

end
