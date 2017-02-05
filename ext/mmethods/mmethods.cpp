/* ////////// LICENSE INFO ////////////////////

 * Copyright (C) 2013 by NYSOL CORPORATION
 *
 * Unless you have received this program directly from NYSOL pursuant
 * to the terms of a commercial license agreement with NYSOL, then
 * this program is licensed to you under the terms of the GNU Affero General
 * Public License (AGPL) as published by the Free Software Foundation,
 * either version 3 of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF 
 * NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
 *
 * Please refer to the AGPL (http://www.gnu.org/licenses/agpl-3.0.txt)
 * for more details.

 ////////// LICENSE INFO ////////////////////*/
// mcmd
// 1.0.0 : 2011/9/16 初期リリース
//
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <cstdlib>

#include <iostream>
#include <unistd.h>
#include <sys/types.h>
#include <ruby.h>
#include <kgmod.h>
#include <kgCSV.h>
#include <kgArgs.h>
#include <kgMessage.h>
#include <kgMethod.h>

using namespace std;
using namespace kglib;

extern "C" {
	void Init_mmethods(void);
}

// =============================================================================
// mrecountメソッド
// =============================================================================
/*
 * call-seq:
 * MCMD::mrecount -> int
 *
 * <b>説明</b> レコード数を返す。
 *
 * <b>書式</b> MCMD::mrecount(options)
 *
 * i=ファイル名
 * -nfn : 一行目を項目名行とみなさない。
 */
VALUE mrecount(int argc, VALUE *argv) try {
	kgArgs args;
	kgEnv  env;
	string name; // rubyスクリプト名
	string argstr;
	int recNo=0; // 返値

	try { // kgmodのエラーはrubyのエラーとは別に検知する(メッセージ表示のため)

		// 引数をopetionsにセット
		VALUE options;
		rb_scan_args(argc, argv,"01",&options);

		// rubyの引数文字列を一旦argstrに退避させてからtoken分割する。
		// 退避させないと、ruby変数としての文字列を変更してしまうことになる。
		if(TYPE(options)==T_NIL){
			argstr="";
		}else if(TYPE(options)==T_STRING){
			argstr=RSTRING_PTR(options);
		}else{
			rb_raise(rb_eRuntimeError,"1st argument must be String");
		}
		vector<char *> opts = splitToken(const_cast<char*>(argstr.c_str()), ' ');

		// 引数文字列へのポインタの領域はここでauto変数に確保する
		kgAutoPtr2<char*> argv;
		char** vv;
		try{
			argv.set(new char*[opts.size()+1]);
			vv = argv.get();
		}catch(...){
			rb_raise(rb_eRuntimeError,"memory allocation error");
		}

		// vv配列0番目はコマンド名
		vv[0]=const_cast<char*>("mrecount");

		size_t vvSize;
		for(vvSize=0; vvSize<opts.size(); vvSize++){
			vv[vvSize+1] = opts.at(vvSize);
		}
		vvSize+=1;

		// 引数をセット!!
		args.add(vvSize,const_cast<const char**>(vv));

		// argsに指定した引数の存在チェック
		args.paramcheck("i=,-nfn",false);

		// -----------------------------------------------------
		// 各種引数の設定

		// i=
		string iName = args.toString("i=",false).c_str();

		// -nfn
		bool nfn   = args.toBool("-nfn");

		kgCSVrec csv;
		csv.open( iName, &env, nfn, 4 );
    csv.read_header();

		while(EOF!=csv.read()) recNo++;
		csv.close();

	}catch(kgError& err){ // kgmod関係エラーのchatch
		err.addModName(name);
		kgMsg msg(kgMsg::ERR, &env);
		msg.output(err.message());
		throw;
	}

	// 件数を返す
	return INT2NUM(recNo);

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_init()");
}

//encodingを考慮した文字列生成
static VALUE str2rbstr(string ptr)
{
	// rb_external_str_new_cstrが定義されているばそちらを使う
	#if defined(rb_external_str_new_cstr)
		return rb_external_str_new_cstr(ptr.c_str());
	#else
		return rb_str_new2(ptr.c_str());
	#endif
}

// =============================================================================
// mheaderメソッド
// =============================================================================
/*
 * call-seq:
 * MCMD::mheader -> int
 *
 * <b>説明</b> 項目名配列を返す。
 *
 * <b>書式</b> MCMD::mheader(options)
 *
 * i=ファイル名
 */

VALUE mheader(int argc, VALUE *argv) try {
	kgArgs args;
	kgEnv  env;
	string name; // rubyスクリプト名
	string argstr;

	try { // kgmodのエラーはrubyのエラーとは別に検知する(メッセージ表示のため)

		// 引数をopetionsにセット
		VALUE options;
		rb_scan_args(argc, argv,"10",&options);

		// rubyの引数文字列を一旦argstrに退避させてからtoken分割する。
		// 退避させないと、ruby変数としての文字列を変更してしまうことになる。
		argstr=RSTRING_PTR(options);
		if(TYPE(options)!=T_STRING){
			rb_raise(rb_eRuntimeError,"1st argument must be String");
		}
		vector<char *> opts = splitToken(const_cast<char*>(argstr.c_str()), ' ');

		// 引数文字列へのポインタの領域はここでauto変数に確保する
		kgAutoPtr2<char*> argv;
		char** vv;
		try{
			argv.set(new char*[opts.size()+1]);
			vv = argv.get();
		}catch(...){
			rb_raise(rb_eRuntimeError,"memory allocation error");
		}

		// vv配列0番目はコマンド名
		vv[0]=const_cast<char*>("mheader");

		size_t vvSize;
		for(vvSize=0; vvSize<opts.size(); vvSize++){
			vv[vvSize+1] = opts.at(vvSize);
		}
		vvSize+=1;

		// 引数をセット!!
		args.add(vvSize,const_cast<const char**>(vv));

		// argsに指定した引数の存在チェック
		args.paramcheck("i=,-nfn",false);

		// -----------------------------------------------------
		// 各種引数の設定

		// i=
		string iName = args.toString("i=",false);

		// -nfn
		bool nfn   = args.toBool("-nfn");

		kgCSVrec csv;
		csv.open( iName, &env, nfn, 4 );
    csv.read_header();

		size_t fldSize=csv.fldSize();
		VALUE names=rb_ary_new2(fldSize);

		if(nfn){
			for(size_t i=0; i<fldSize; i++){
				rb_ary_store( names, i, INT2FIX(i) );
			}
		}else{
			for(size_t i=0; i<fldSize; i++){
				rb_ary_store( names, i, str2rbstr( csv.fldName(i).c_str()) );
			}
		}
		csv.close();

		return names;

	}catch(kgError& err){ // kgmod関係エラーのchatch
		err.addModName(name);
		kgMsg msg(kgMsg::ERR, &env);
		msg.output(err.message());
		throw;
	}

	// 件数を返す
	//return INT2NUM(recNo);

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_init()");
}

void Init_mmethods(void) {
	// モジュール定義:MCMD::xxxxの部分
	VALUE mcmd=rb_define_module("MCMD");

  rb_define_module_function(mcmd,"mrecount" , (VALUE (*)(...))mrecount , -1);
  rb_define_module_function(mcmd,"mheader"  , (VALUE (*)(...))mheader  , -1);
}

