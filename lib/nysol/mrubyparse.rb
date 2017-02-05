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
require 'nysol/mcmd'

module MCMD
	class MrubyParse
		@@ST_RESERVE_WORD = ["class","module","if","unless","def"]
		@@ED_RESERVE_WORD = ["end"]

		@@ST_RESERVE_REG  = @@ST_RESERVE_WORD.maddPrefix(["^","\\s+"]).maddSuffix(["$","\\s+"])
		@@ED_RESERVE_REG  = @@ED_RESERVE_WORD.maddPrefix(["^","\\s+"]).maddSuffix(["$","\\s+","\\."])
		@@RESERVE_REG     = @@ST_RESERVE_REG.concat(@@ED_RESERVE_REG)
  	 

		@@ST_BLOCK_WORD = [["{"],["do"]]
		@@ED_BLOCK_WORD = [["}"],["end"]]
		#@@ST_BLOCK_REG  = @@ST_BLOCK_WORD.maddPrefix(["^","\\s+"]).maddSuffix(["$","\\s+"])
		#@@ED_BLOCK_REG  = @@ED_BLOCK_WORD.maddPrefix(["^","\\s+"]).maddSuffix(["$","\\s+"])
		@@ST_BLOCK_PTN  = [@@ST_BLOCK_WORD[0].maddPrefix("\\s*").maddSuffix("\\s*"),@@ST_BLOCK_WORD[1].maddPrefix(["^","\\s+"]).maddSuffix(["$","\\s+"])]
		@@ED_BLOCK_PTN  = [@@ED_BLOCK_WORD[0].maddPrefix("\\s*").maddSuffix("\\s*"),@@ED_BLOCK_WORD[1].maddPrefix(["^","\\s+"]).maddSuffix(["$","\\s+"])]


		def initialize(infn,lin,kwd,value)
			@infn = infn
			@limLin = lin 
			@kwd =kwd
			@values =value
			@ldata = ""
			@blktype = 0 
			@stCnt = 0
			@edCnt = 0 
			@stBLKCnt = 0
			@edBLKCnt = 0 
			@recCnt = 0
			@outFLG = false
			@argST_FLG = false
			@argED_FLG = false
			@reqinfo = false
			@state = 0
			@outdata =[]
			@reqdata =[]
			@argsV =[]
			@outline =""
			@blkPtn = 0

		end

		def skip_space(pos)
			return nil if pos==nil
			rpos = @ldata.index(/\S/,pos)
			if rpos == nil then
				if @ldata.size == 0 then
					rpos = pos
				else
					rpos = @ldata.size-1
				end
			end
			return rpos
		end

		def match_Reserve(ldata,pos)
			return nil if pos ==nil
			lldata = ldata[pos..-1]
			
			@@ST_RESERVE_WORD.each{|reserv|
				return reserv if lldata.index(/^#{reserv}/)
			}
			@@ED_RESERVE_WORD.each{|reserv|
				return reserv if lldata.index(/^#{reserv}/)
			}
			return nil
		end

		def match_BlkReserve(ldata,pos)
			return nil if pos ==nil
			lldata = ldata[pos..-1]
			@@ST_BLOCK_WORD[@blktype].each{|reserv|
				return reserv if lldata.index(/^#{reserv}/)
			}
			@@ED_BLOCK_WORD[@blktype].each{|reserv|
				return reserv if lldata.index(/^#{reserv}/)
			}
			return nil
		end


		def analyze_blk_sub
			if @ldata =~ /^\s*#/ then
				@ldata =""
				return 			
			end
			if @edCnt == @stCnt and @ldata =~ /^\s*require\s/ then
				@outdata << @ldata
				@ldata =""
				return
			end
			pos = 0
			pos = @ldata.index(/#{@@RESERVE_REG.join('|')}/,pos)
			pos = skip_space(pos)
			kwd = match_Reserve(@ldata,pos)
			if pos == nil then
				@outline << @ldata if @outFLG
				pos = @ldata.size
			elsif kwd == "end" then
				@edCnt +=1
				pos += kwd.size
				@outline << @ldata[0...pos] if @outFLG
				@outFLG =false if @edCnt == @stCnt
			elsif kwd == "if" || kwd == "unless" then
				@stCnt +=1 if @ldata[0...pos].index(/\S/) == nil
				pos += kwd.size
				@outline << @ldata[0...pos] if @outFLG
			else	
				@stCnt +=1
				pos += kwd.size
				@outFLG =true
				@outline << @ldata[0...pos] if @outFLG
			end
			@ldata = @ldata[pos..-1]
			# 行終了
			if @ldata.size==0 then
				if @outline.size != 0 then
					@outdata << @outline 
					@recCnt += 1
				end
				@recCnt = 0 if @edCnt == @stCnt
			end
		end

		# skip,add_stcnt,add_edcnt,chgoutF
		def analyze_blk_start
			sp = @ldata.match(/(.*)#{@kwd}(#{@@ST_BLOCK_PTN[0].join('|')}|#{@@ST_BLOCK_PTN[1].join('|')})(.*)/)
			sp = @ldata.match(/(.*)#{@kwd}\s*\(.*\)\s*(#{@@ST_BLOCK_PTN[0].join('|')}|#{@@ST_BLOCK_PTN[1].join('|')})(.*)/) if sp == nil
			@blkPtn = 1 if sp[2].include?("do")
			@ldata = sp[3]
		end

		def analyze_args
			@ldata.lstrip!
			return if @ldata.size==0
			unless @argST_FLG then
				raise "format ERROR" if @ldata[0]!="|"
				@ldata=@ldata[1..-1]
				@argST_FLG = true
			end
			out=""
			unless @argED_FLG then
				pos=0
				while pos <  @ldata.size do
					case @ldata[pos]
					when ","
						@argsV << out
						out =""
					when "|"
						@argsV << out
						out =""
						@argED_FLG = true
					else
						out << @ldata[pos]
					end
					pos += 1
					break if @argED_FLG
				end
				@ldata = @ldata[pos..-1]
			end
		end

		def analyze_blk
			pos = 0 
			loop{
				pos = @ldata.index(/(#{@@ST_BLOCK_PTN[@blkPtn].join('|')}|#{@@ED_BLOCK_PTN[@blkPtn].join('|')})(.*)/)
				pos = skip_space(pos)
				kwd = match_BlkReserve(@ldata,pos)
				if pos == nil then
					@outline << @ldata
					pos = @ldata.size
				else
					case kwd
					when "do","{"
						@stBLKCnt+=1
					when "end","}"
						@edBLKCnt+=1
					end
					if @stBLKCnt == @edBLKCnt then
						@outline << @ldata[0...pos]
						pos = pos+kwd.size
					else
						pos = pos+kwd.size
						@outline << @ldata[0...pos]
					end
				end
				@ldata = @ldata[pos..-1]
				break if @ldata.size == 0
				break if @stBLKCnt == @edBLKCnt 
			}
		end

		def output(outfn)
			File.open(outfn,"w"){|ofp|
			ofp.puts("#!/usr/bin/env ruby")
			ofp.puts("# -*- coding: utf-8 -*- ")
			File.open(@infn,"r"){|ifp|
				ifp.each_line do | ldata |
					@outline = "" 
					@ldata = ldata.chomp
					loop{
						break if @ldata.size==0
						case @state
						when 0 # kwd(m2each) block前
							if ifp.lineno == @limLin then 
								@state = 1 ; next ; 
							end
							analyze_blk_sub()
						when 1 # kwd(m2each) 行
							analyze_blk_start()
							@outFLG = false
							@stBLKCnt += 1
							@state = 2
							outrqCHK =[]
							@recCnt.times{ #requireは出力する
								chkword = @outdata.pop 
								outrqCHK << chkword if @ldata =~ /^\s*require\s/ 
							}
							@outdata.each{|ld| ofp.puts(ld) }
							outrqCHK.each{|ld| ofp.puts(ld) }
							@values.each {|ld| ofp.puts(ld) }
							@outdata=[]
						when 2 # kwd(m2each) 引数
							analyze_args()
							if @argED_FLG then
								@argsV.each_with_index{|v,i|
									if i==0 then
										ofp.puts("#{v} = ARGV[#{i}].split(',')")
										ofp.puts("#{v} = #{v}[0] if #{v}.size==1")
									else
										ofp.puts("#{v} = ARGV[#{i}].to_i")
									end
								}
								@state = 3
							end
						when 3 # kwd(m2each) ブロック
							analyze_blk()
							if @stBLKCnt == @edBLKCnt || @ldata.size == 0 then
								ofp.puts(@outline)
								@state = 4 if @stBLKCnt == @edBLKCnt
							end
						when 4 # end check
							analyze_blk_sub()
							if @edCnt == @stCnt then
								@outdata=[]
								@state = 5
							end
						when 5 # end check
							analyze_blk_sub()
						end
						break if @ldata.size==0
					}
				end
				@outdata.each{|ld| ofp.puts(ld) }
			}
			}
		end
	end

	# inf:ソースファイル , lin:読み込み開始業 out:出力ファイル名 kwd:m2each,出力するローカル変数
	def MCMD::outputblk(inf,lin,outf,kwd,values=[])

		
		s_char_ex = ["\\s+class\\s+|^class\\s+|\\s+class$|^class$",
								"\\s+module\\s+|^module\\s+|\\s+module$|^module$",
								"\\s+if\\s+|^if\\s+|\\s+if$|^if$",
								"\\s+def\\s+|^def\\s+|\\s+def$|^def$" ]
		e_char_ex = ["\\s+end\\s+|^end\\s+|\\s+end\.|^end\.|\\s+end$|^end$"]


		s_char = ["\\s*{\\s*","\\s+do\\s+|^do\\s+|\\s+do$|^do$" ]
		e_char = ["\\s*}\\s*","\\s+end\\s+|^end\\s+|\\s+end\.|^end\.|\\s+end$|^end$"]
		regpos = 0
		nowL=0
		start = false
		arg   = false
		arg_s   = false
		blk_e   = false
		s_ch_cnt= 0
		e_ch_cnt= 0
		oscript = "" 
		args=[]
		reqiureinfo=[]
		afterinfo=[]
		stcnt_ex =0
		edcnt_ex =0
		outF=false
		reccnt=0
		#開始行kwdの位置を決定してその後ブロックを抜き出す
		File.open(outf,"w"){|ofp|
		File.open(inf,"r"){|ifp|
			while ldata = ifp.gets do
				nowL+=1
				if nowL	< lin then
					if ldata =~ /^\s*require\s|^\s*#/
						reqiureinfo << ldata 
						reccnt +=1
						next
					end
					ofset_e=0
					out_e=""
					loop {
						pos_e = ldata.index(/(#{s_char_ex.join('|')}|#{e_char_ex[0]})/,ofset_e)
						if pos_e != nil then
							while pos_e < ldata.length do 
								break unless ldata[pos_e].match(/\s/)
								pos_e+=1
							end
							case ldata[pos_e]
							when "c" then
								pos_e+=5
								stcnt_ex+=1
								outF = true
								out_e << ldata[0...pos_e] if outF
							when "m" then
								pos_e+=6
								stcnt_ex+=1
								outF = true
								out_e << ldata[0...pos_e] if outF
							when "d" then
								pos_e+=3
								stcnt_ex+=1
								outF = true
								out_e << ldata[0...pos_e] if outF
							when "i" then
								## 後ろif(空白以外あり)
								if ldata[0...pos_e].index(/\S/) != nil then
									pos_e+=2
									out_e << ldata[0...pos_e]	if outF
								else
									pos_e+=2
									out_e << ldata[0...pos_e]	if outF	
									stcnt_ex+=1							
								end
								
							when "e" then
								pos_e+=3
								edcnt_ex+=1
								out_e << ldata[0...pos_e] if outF
								outF = false if stcnt_ex == edcnt_ex
								
							end
						else
							out_e << ldata if outF
							reqiureinfo << out_e 
							reccnt +=1
							reccnt =0 if stcnt_ex == edcnt_ex
							break
						end
						ldata=ldata[pos_e..-1]
					}
					next
				end
				# 開始チェック
				unless start  then
					# start 位置 "v1".m2each"v2" "v3"
					sp = ldata.match(/(.*)#{kwd}(#{s_char[0]}|#{s_char[1]})(.*)/)
					sp = ldata.match(/(.*)#{kwd}\s*\(.*\)\s*(#{s_char[0]}|#{s_char[1]})(.*)/) if sp == nil
					regpos = 1 if sp[2].include?("do")
					ldata = sp[3]
					start = true 
					outF =false
					s_ch_cnt+=1
					reccnt.times{ reqiureinfo.pop }
					reqiureinfo.each{|ld| ofp.puts(ld) }
					values.each{|ld| ofp.puts(ld) }
				end 
				# argsチェック
				unless arg then
					ldata.lstrip!
					next if ldata.length == 0 
					unless arg_s then
						raise "format error" if ldata[0]!="|"
						ldata = ldata[1..-1]
						arg_s =true
					end
					pos=0
					out =""
					while pos < ldata.length do 
						case ldata[pos]
						when ","
							args << out
							out =""	
						when "|"
							args << out
							out =""	
							arg = true
							pos += 1
							break
						else
							out << ldata[pos]
						end
						pos += 1
					end
					next unless arg
					ldata =ldata[pos..-1]
					args.each_with_index{|d,i|
						if i==0 then
							ofp.puts("#{d} = ARGV[#{i}].split(',')")
							ofp.puts("#{d} = #{d}[0] if #{d}.size==1")

						else 
							ofp.puts("#{d} = ARGV[#{i}].to_i")						
						end
					}
				end
				unless blk_e then
					offset=0
					out =""
					loop {
						pos = ldata.index(/#{s_char[regpos]}|#{e_char[regpos]}/,offset)
						if pos == nil then
							out = ldata
							break	
						end
						while pos < ldata.length do 
							break unless ldata[pos].match(/\s/)
							pos+=1
						end
						case ldata[pos]
						when "d" then
							s_ch_cnt+= 1	
							offset = pos+2
						when "e" then
							e_ch_cnt+= 1
							offset = pos+3			
						when "{" then
							s_ch_cnt+= 1
							offset = pos+1
						when "}" then
							e_ch_cnt+= 1						
							offset = pos+1
						end
						if s_ch_cnt == e_ch_cnt then
							out = ldata[0...pos]
							ldata =ldata[pos..-1]
							break
						end
					}
					ofp.puts out
					blk_e = true if s_ch_cnt == e_ch_cnt
					next unless blk_e					
				end
				# block以降
				if ldata =~ /^\s*require\s|^\s*#/
					afterinfo << ldata 
					reccnt +=1
					next
				end
				ofset_e=0
				out_e=""
				loop {
					pos_e = ldata.index(/(#{s_char_ex.join('|')}|#{e_char_ex[0]})/,ofset_e)
					if pos_e != nil then
						while pos_e < ldata.length do 
							break unless ldata[pos_e].match(/\s/)
							pos_e+=1
						end
						case ldata[pos_e]
							when "c" then
								pos_e+=5
								stcnt_ex+=1
								out_e << ldata[0...pos_e] if outF
							when "m" then
								pos_e+=6
								stcnt_ex+=1
								out_e << ldata[0...pos_e] if outF
							when "d" then
								pos_e+=3
								stcnt_ex+=1
								out_e << ldata[0...pos_e] if outF
							when "i" then
								## 後ろif(空白以外あり)
								if ldata[0...pos_e].index(/\S/) != nil then
									pos_e+=2
									out_e << ldata[0...pos_e]	if outF
								else
									pos_e+=2
									out_e << ldata[0...pos_e]	if outF
									stcnt_ex+=1							
								end
								
							when "e" then
								pos_e+=3
								edcnt_ex+=1
								out_e << ldata[0...pos_e] if outF
								outF = false if stcnt_ex == edcnt_ex
								
							end
						else
							out_e << ldata if stcnt_ex != edcnt_ex &&  outF
							afterinfo << out_e 
							reccnt +=1
							reccnt =0 if stcnt_ex == edcnt_ex
							break
						end
						ldata=ldata[pos_e..-1]
				}
			end
			afterinfo.each{|ld| ofp.puts(ld) }
		}
		}

	end


end

if __FILE__ == $0 then
	infn= ARGV[0]
	lin= ARGV[1].to_i
	tag= ARGV[2]

	MCMD::MrubyParse.new(infn,lin,tag,[]).output("xxxx_#{tag}_#{lin}")

end