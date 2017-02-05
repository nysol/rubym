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
// =============================================================================
// mcsvout.cpp CSV入力クラス
// =============================================================================
#include <unistd.h>
#include <sys/types.h>
#include <ruby.h>
#include <kgmod.h>
#include <kgCSVout.h>
#include <kgArgFld.h>
#include <kgMethod.h>

using namespace std;
using namespace kglib;

extern "C" {
	void Init_mcsvout(void);
}

// =============================================================================
// CSV出力クラス
// =============================================================================
class mcsvout : public kgMod 
{
	vector<kgstr_t> fldNames_; // f=引数

public:
	VALUE          object_;    // mcsvoutオブジェクト(rb_yieldで必要)
  kgCSVout       oFile_;     // 出力ファイル(o=)
	int            sigDigits_; // float型有効桁数(sig=)
	size_t         fldSize_;   // 出力項目数(size=)
	bool           noFldName_; // 項目名出力なしフラグ(-nfn)
	string        fsName_;
	string         boolStr_;
	vector<char *> bools_;
	kgArgFld       fld_;

	mcsvout(void){
		_name    = "mcsvout";
		_version = "1.0";
	};
	
	virtual ~mcsvout(void){
	}

	size_t oRecNo(void) const{
		return oFile_.recNo();
	}

	void addFldName(const char* fldName){
		fldNames_.push_back(fldName);
	}

	// ファイルオープン&項目名出力
	void open() try {

		oFile_.open(fsName_.c_str(), _env, noFldName_);
		if(! noFldName_) oFile_.writeFldNameCHK(fldNames_);
		oFile_.flush();
	}catch(...){
		throw;
	}

	// pure virtual関数なので定義だけしておく。
	int run(){ return 0;}

	// ファイルクローズ
	void close(void) try 
	{ 
		oFile_.close();
	}catch(...){
		throw;
	}

};

// =============================================================================
// rMmcsvout クラス(mcsvoutクラスのrubyラッパ)
//  機能: 1) kgEnvとコマンドライン引数のメモリを確保する
//        2) 正常終了,エラー終了の統一的メソッドを提供する
// =============================================================================
class rMcsvout 
{
public:
	kgEnv  env;
	string argstr; // rubyの引数をコピーして格納するための変数
	kgAutoPtr2<char*> argv;
	mcsvout* mod; // 一度実行(RUN)されると0となる．

private:
	void freeMod() try 
	{
		if(mod!=0){ delete mod; }
		mod=0;	
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at freeMod()");
	}

public:
	~rMcsvout(void){ 
		if(mod!=0){ 
			successEnd();  
			mod=0;
		}
	}

	// エラー終了メソッド
	void errorEnd(kgError& err) try 
	{
		mod->close();
		mod->errorEnd(err);
		freeMod();
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at errorEnd()");
	}

	// 正常終了メソッド
	void successEnd() try 
	{
		mod->close();
		mod->successEnd();
		freeMod();
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at successEnd()");
	}
};

// =============================================================================
// 公開メソッド
// =============================================================================
// -----------------------------------------------------------------------------
// NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW
// def initialize(args,arrayHashFlag)
// 引数の設定(rubyで指定されたargvをkgmodにchar*として渡す)
// -----------------------------------------------------------------------------
VALUE csvout_init(int argc, VALUE *argv, VALUE self) try 
{
	rMcsvout* rmod;
	Data_Get_Struct(self,rMcsvout,rmod);

	try { 

		// 引数をoptionsにセット
		VALUE options;
		rb_scan_args(argc, argv,"01",&options);

		// rubyの引数文字列を一旦rmod->argstrに退避させてからtoken分割する。
		// 退避させないと、ruby変数としての文字列を変更してしまうことになる。
		if(TYPE(options)==T_NIL){
			rmod->argstr="";
		}else if(TYPE(options)==T_STRING){
			rmod->argstr=RSTRING_PTR(options);
		}else{
			rb_raise(rb_eRuntimeError,"1st argument must be String");
		}
		vector<char *> opts = splitToken(const_cast<char*>(rmod->argstr.c_str()), ' ',true);

		// 引数文字列へのポインタの領域はここでauto変数に確保する
		char** vv;
		try{
			rmod->argv.set(new char*[opts.size()+1]);
			vv = rmod->argv.get();
		}catch(...){
			throw kgError("memory allocation error");
		}

		// 引数セット vv配列0番目はコマンド名
		vv[0]=const_cast<char*>(rmod->mod->name());
		size_t vvSize;
		for(vvSize=0; vvSize<opts.size(); vvSize++){
			vv[vvSize+1] = opts.at(vvSize);
		}
		vvSize+=1;

		// modの初期化引数チェック
		rmod->mod->init(vvSize, const_cast<const char**>(vv), &rmod->env);
		rmod->mod->args()->paramcheck("o=,f=,size=,precision=,bool=",false);

		// -----------------------------------------------------
		// 各種引数の設定  o=,f=,size=,precision=,bool=
		// -----------------------------------------------------
		rmod->mod->fsName_ =  rmod->mod->args()->toString("o=",false);

		rmod->mod->fldSize_ =0;
		vector<kgstr_t> vs;
		vs = rmod->mod->args()->toStringVector("f=",false);
		if(vs.size()>0){
			rmod->mod->noFldName_=false;
			rmod->mod->fldSize_ = vs.size();
			for(size_t i=0; i<rmod->mod->fldSize_; i++){
				rmod->mod->addFldName(vs.at(i).c_str());
			}
		}

		string sizeStr = rmod->mod->args()->toString("size=",false);
		if(sizeStr.size()>0){
			rmod->mod->noFldName_=true;
			rmod->mod->fldSize_ = atoi(sizeStr.c_str());
		}
		if(vs.size()==0&&sizeStr.size()==0){
			throw kgError("f= or size= must be specified ");		
		}

		string sigStr  = rmod->mod->args()->toString("precision=",false);
		string boolStr = rmod->mod->args()->toString("bool=",false);

		// sig=: 有効桁数
		if(sigStr.size()>0){
			int precision=atoi(sigStr.c_str());
			rmod->mod->env()->precision(precision);
		}

		// bool=: true,falseの文字列
		if(boolStr.size()>0){
			rmod->mod->boolStr_=boolStr;
			rmod->mod->bools_ = splitToken(const_cast<char*>(rmod->mod->boolStr_.c_str()), ',');
			if(rmod->mod->bools_.size()!=2){
				rb_raise(rb_eRuntimeError,"bools= takes two values(ex. bools=true,false) separated by comma.");
			}
		}else{
			rmod->mod->bools_.push_back(const_cast<char*>("1"));
			rmod->mod->bools_.push_back(const_cast<char*>("0"));
		}

		// ファイルオープン
		rmod->mod->open();

		// ブロック引数があればyield実行
		if(rb_block_given_p()){
			rb_yield(rmod->mod->object_);
			rmod->successEnd();
		}

	}catch(kgError& err){ // kgmod関係エラーのchatch
		rmod->errorEnd(err); throw;
	}
	return self;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvout_init");
}

// ------------------------------------------------------------------
// WRITE WRITE WRITE WRITE WRITE WRITE WRITE WRITE WRITE WRITE WRITE
// ------------------------------------------------------------------
VALUE csvout_write(int argc, VALUE *argv, VALUE self) try 
{
	rMcsvout* rmod;
	Data_Get_Struct(self,rMcsvout,rmod);

	try 
	{ 
		if(rmod->mod == 0){
			rb_raise(rb_eRuntimeError,"csv file is not opened");
		}

		// 引数をvalsにセット
		VALUE vals;
		rb_scan_args(argc, argv,"1",&vals);

		size_t size   =RARRAY_LEN(vals);
		size_t fldSize=rmod->mod->fldSize_;
		kgCSVout& oFile =rmod->mod->oFile_;

		// 配列の内容の出力
		if(TYPE(vals)==T_ARRAY){

			// 配列のサイズが項目名サイズより大きい時は、項目名サイズ分のみ出力する。
			if(size>fldSize) size=fldSize;
			for(size_t i=0; i<size; i++){

				VALUE v = RARRAY_PTR(vals)[i];

				switch(TYPE(v)){
				case T_STRING:
					if(i==fldSize-1) oFile.writeStr(RSTRING_PTR(v),true);
					else             oFile.writeStr(RSTRING_PTR(v),false);
					break;
				case T_FIXNUM:
					if(i==fldSize-1) oFile.writeLong(FIX2LONG(v),true);
					else             oFile.writeLong(FIX2LONG(v),false);
					break;
				case T_BIGNUM:
					if(i==fldSize-1) oFile.writeLong(NUM2LONG(v),true);
					else             oFile.writeLong(NUM2LONG(v),false);
					break;
				case T_FLOAT:
					if(i==fldSize-1) oFile.writeDbl(NUM2DBL(v),true);
					else             oFile.writeDbl(NUM2DBL(v),false);
					break;
				case T_TRUE:
					if(i==fldSize-1) oFile.writeStr(rmod->mod->bools_.at(0),true);
					else             oFile.writeStr(rmod->mod->bools_.at(0),false);
					break;
				case T_FALSE:
					if(i==fldSize-1) oFile.writeStr(rmod->mod->bools_.at(1),true);
					else             oFile.writeStr(rmod->mod->bools_.at(1),false);
					break;
				default:
					if(i==fldSize-1) oFile.writeStr("",true);
					else             oFile.writeStr("",false);
				}
			}
		}else{
			rb_raise(rb_eRuntimeError,"write() function takes Array");
		}

		// 配列のサイズが項目名サイズより小さい時は、null値を出力。
		if(size<fldSize){
			for(size_t i=size; i<fldSize; i++){
				if(i==fldSize-1) oFile.writeStr("",true);
				else             oFile.writeStr("",false);
			}
		}

	}catch(kgError& err){ // kgmod関係エラーのchatch
		rmod->errorEnd(err); throw;
	}

	return Qtrue;

}catch(...){
	rb_raise(rb_eRuntimeError,"at csvout_write()");
}

// ------------------------------------------------------------------
// CLOSE CLOSE CLOSE CLOSE CLOSE CLOSE CLOSE CLOSE CLOSE CLOSE CLOSE
// ------------------------------------------------------------------
VALUE csvout_close(VALUE self) try 
{
	rMcsvout* rmod;
	Data_Get_Struct(self,rMcsvout,rmod);

	try { 
		rmod->successEnd();

	}catch(kgError& err){ 

		rmod->errorEnd(err); throw;

	}

	return Qtrue;

}catch(...){
	rb_raise(rb_eRuntimeError,"at csvout_close()");
}
// =============================================================================
// メモリ解放
// kgRubyModの領域開放(GC時にrubyにより実行される)(xxx_alloc()にて登録される)
// =============================================================================
void csvout_free(rMcsvout* rmod) try {
	if(rmod!=0){
		delete rmod;
	}
}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvout_free()");
}

// =============================================================================
// インスタンス化される時のメモリ確保
// =============================================================================
VALUE mcsvout_alloc(VALUE klass) try {
	rMcsvout* rmod=new rMcsvout;
	rmod->mod = new mcsvout;
	VALUE object=Data_Wrap_Struct(klass,0,csvout_free,rmod);
	rmod->mod->object_ = object;
	return object;
}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvout_alloc()");
}

void Init_mcsvout(void) {
	// モジュール定義:MCMD::xxxxの部分
	VALUE mcmd=rb_define_module("MCMD");

	VALUE mcsvout;
	mcsvout=rb_define_class_under(mcmd,"Mcsvout",rb_cObject);
	rb_define_alloc_func(mcsvout, mcsvout_alloc);
	rb_define_method(mcsvout,"initialize", (VALUE (*)(...))csvout_init ,-1);
	rb_define_method(mcsvout,"write",      (VALUE (*)(...))csvout_write,-1);
	rb_define_method(mcsvout,"close",      (VALUE (*)(...))csvout_close,0);
}

