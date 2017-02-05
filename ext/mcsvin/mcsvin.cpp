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
// mcsvin.cpp CSV入力クラス
// =============================================================================
#include <iostream>
#include <unistd.h>
#include <sys/types.h>
#include <ruby.h>
#include <kgmodincludesort.h>
#include <kgCSV.h>
#include <kgArgFld.h>
#include <kgMethod.h>

extern "C" {
	void Init_mcsvin(void);
}

using namespace std;
using namespace kglib;
using namespace kgmod;

// -----------------------------------------------------------------------------
// encodingを考慮した文字列生成
// -----------------------------------------------------------------------------
//static VALUE str2rbstr(const char *ptr)
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
// CSV入力クラス
// =============================================================================
class mcsvin : public kgModIncludeSort
{
	//kgCSV*   iFile_;     // 次のいずれかの変数へのポインタ
	//kgCSVkey iFileKey_;  // 入力ファイル(k=指定がある時)
	//kgCSVfld iFileFld_;  // 入力ファイル(k=指定がない時)
	kgCSVkey iFile_;     // 入力ファイル統一


	kgArgFld kField_;    // k=
	size_t fldSize_;

	// each用
	void runHashKey(void);
	void runArrayKey(void);
	void runHash(void);
	void runArray(void);

	// ges用
	VALUE getsHashKey(void);
	VALUE getsArrayKey(void);
	VALUE getsHash(void);
	VALUE getsArray(void);


public:
	//kgCSV*   iFile_;     // 次のいずれかの変数へのポインタ
	string  fsName_;   // ファイル名(i=)

	VALUE        names_;   // 項目名(f=) or 項目数(size=)
	bool         hasKey_;  // k=が指定されているかどうか。
	bool         hasSkey_;  // s=が指定されているかどうか。
	bool         byArray_; // valをArrayに格納するフラグ
	bool 				 kbFlag_;  //key-breakを判定するフラグ
	bool 				 qflg_;

	mcsvin(void){ // コンストラクタ
		_name    = "mcsvin";
		_version = "2.0";
		byArray_ = false;
		hasKey_  = false;
		kbFlag_  = true;
	};

	virtual ~mcsvin(void){ close(); }

	// -----------------------------------------------------------------------------
	// 処理行数取得
	// -----------------------------------------------------------------------------
	// -----------------------------------------------------------------------------
	// ファイルオープン＆ヘッダ読み込みSUBルーチン
	// -----------------------------------------------------------------------------
	void openByKey() try{ 
		iFile_.open(fsName_.c_str(), _env,_args.toBool("-nfn"));
		iFile_.read_header();
		vector<kgstr_t> vs = _args.toStringVector("k=",false);
		vector<kgstr_t> vss = _args.toStringVector("s=",false);

		if(!qflg_){
			vector<kgstr_t> vsk	= vs;
			vsk.insert(vsk.end(),vss.begin(),vss.end());
			sortingRun(&iFile_,vsk);
		}
		kField_.set(vs,  &iFile_, _fldByNum);
  	iFile_.setKey(kField_.getNum());

	}catch(...){
		throw;
	}
	void openByfld() try{ 
		iFile_.open(fsName_.c_str(), _env,_args.toBool("-nfn"));
		iFile_.read_header();
//		iFile_=&iFileFld_;
	}catch(...){
		throw;
	}

	// -----------------------------------------------------------------------------
	// ファイルオープン＆ヘッダ読み込み
	// -----------------------------------------------------------------------------
	void open() try { 
		rb_gc_start(); //gcのタイミングは要再考
		//k=有り無しで処理を変える
		try {
			if(hasKey_||hasSkey_){ openByKey();}
			else			 { openByfld();}
 		}catch(...){//一度だけリトライ
 			try{
	 			rb_gc_start();
				if(hasKey_||hasSkey_){ 
					iFile_.clear();
					openByKey();
				}
				else{
					iFile_.clear();
					openByfld();
				}
 			}catch(...){
 				throw;
 			}
 		}
		fldSize_=iFile_.fldSize();

	}catch(...){
		throw;
	}

	// -----------------------------------------------------------------------------
	// ファイルクローズ
	// -----------------------------------------------------------------------------
	void close(void) try {
		iFile_.close();
	}catch(...){ 
		throw; 
	}

	// -----------------------------------------------------------------------------
	//アクセッサ
	// -----------------------------------------------------------------------------
	bool   nfn()		 const{ return iFile_.noFldName();}
	size_t fldsize() const{ return fldSize_;}
	string fldName(size_t i){ return iFile_.fldName(i);}

	size_t iRecNo()  const{ 
		return iFile_.recNo();
	}


	// -----------------------------------------------------------------------------
	// 実行関数
	// -----------------------------------------------------------------------------
	int run();
	VALUE gets();

};

// -----------------------------------------------------------------------------
// Array格納、Key指定なし
// -----------------------------------------------------------------------------
void mcsvin::runArray(void) try {

	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return; }

	// 一行ずつ読み込みyield実行
	VALUE fldArray=0;
	while( EOF != iFile_.read() ) {

		if((iFile_.status() & kgCSV::End )) break;

		fldArray=rb_ary_new2(fldSize_);
		for(int i=0; i<static_cast<int>(fldSize_); i++){
			VALUE str;
			if(*iFile_.getVal(i)=='\0'){ str=Qnil;  } // nullはQnil
			else { str=str2rbstr(iFile_.getVal(i)); }
			rb_ary_store( fldArray,i,str );
		}

		// yield実行(blockの実行)
		rb_yield_values(1,fldArray);
	}
	close();

}catch(...){
	throw;
}

// -----------------------------------------------------------------------------
// Hash格納、Key指定なし
// -----------------------------------------------------------------------------
void mcsvin::runHash(void) try {

	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return; }

	// 一行ずつ読み込みyield実行
	while( EOF != iFile_.read() ) {
		if((iFile_.status() & kgCSV::End )) break;
		VALUE fldHash=rb_hash_new();
		for(int i=0; i<static_cast<int>(fldSize_); i++){
			VALUE str;
			if(*iFile_.getVal(i)=='\0') { str=Qnil;}// nullはQnil
			else { str=str2rbstr(iFile_.getVal(i));}
			rb_hash_aset( fldHash,str2rbstr( iFile_.fldName(i).c_str()), str );
		}

		// yield実行(blockの実行)
		rb_yield_values(1,fldHash);
	}
	close();

}catch(...){
	throw;
}

// -----------------------------------------------------------------------------
// Array格納、Key指定あり
// -----------------------------------------------------------------------------
void mcsvin::runArrayKey(void) try {

	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return; }

	// キーブレイクフラグ(last)
	VALUE keybreakBot_rb;

	// キーブレイクフラグ(first)
	VALUE keybreakTop_rb;

	// 一行ずつ読み込みyield実行
	while( EOF != iFile_.read() ) {

		if( iFile_.begin() ){
			kbFlag_=true;
			continue;
		}

		if( kbFlag_ ){ keybreakTop_rb=Qtrue; } 
		else				 { keybreakTop_rb=Qfalse;}

		if( iFile_.keybreak() ){
			keybreakBot_rb=Qtrue;
			kbFlag_=true;
		}else{
			keybreakBot_rb=Qfalse;
			kbFlag_=false;
		}

		// 項目値配列
		VALUE fldArray=rb_ary_new2(fldSize_);
		for(int i=0; i<static_cast<int>(fldSize_); i++){			
			VALUE str;
			if(*iFile_.getOldVal(i)=='\0'){ str=Qnil; }// nullはQnil
			else { str=str2rbstr(iFile_.getOldVal(i));}
			rb_ary_store( fldArray,i,str );
		}

		// yield実行(blockの実行)
		rb_yield_values(3,fldArray,keybreakTop_rb,keybreakBot_rb);
	}
	close();
	
}catch(...){
	throw;
}

// -----------------------------------------------------------------------------
// Hash格納、Key指定あり
// -----------------------------------------------------------------------------
void mcsvin::runHashKey() try {

	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return; }

	// キーブレイクフラグ(last)
	VALUE keybreakBot_rb;

	// キーブレイクフラグ(first)
	VALUE keybreakTop_rb;

	// 一行ずつ読み込みyield実行
	while( EOF != iFile_.read() ) {

		if(iFile_.begin()){
			kbFlag_=true;
			continue;
		}

		if( kbFlag_ ) { keybreakTop_rb=Qtrue; } 
		else				  { keybreakTop_rb=Qfalse;}

		if( iFile_.keybreak() ){
			keybreakBot_rb=Qtrue;
			kbFlag_=true;
		}else{
			keybreakBot_rb=Qfalse;
			kbFlag_=false;
		}

		VALUE fldHash=rb_hash_new();
		for(int i=0; i<static_cast<int>(fldSize_); i++){
			VALUE str;
			if(*iFile_.getOldVal(i)=='\0'){ str=Qnil; }// nullはQnil
			else { str=str2rbstr(iFile_.getOldVal(i));}
			rb_hash_aset( fldHash,str2rbstr( iFile_.fldName(i).c_str()), str );

		}

		// yield実行(blockの実行)
		rb_yield_values(3,fldHash,keybreakTop_rb,keybreakBot_rb);
	}
	close();
	
}catch(...){
	throw;
}

// ======================================================================
// EACH
// ======================================================================
int mcsvin::run() try 
{
	// -nfnの場合は自動的にArray
	if(byArray_ || nfn()){
		if(hasKey_) runArrayKey();
		else        runArray();
	}else{
		if(hasKey_) runHashKey();
		else        runHash();
	}
	// ここでソートスレッドの終了確認
	th_cancel();
	return 0;

}catch(...){
	throw;
}

// -----------------------------------------------------------------------------
// Array格納、GETS
// -----------------------------------------------------------------------------
VALUE mcsvin::getsArray() try 
{
	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return Qnil; }

	// 項目値配列
	VALUE datas=rb_ary_new2(fldSize_);
	
	// 一行ずつ読み込み
	if ( iFile_.read() == EOF ){ return Qnil; }
	
	for(int i=0; i<static_cast<int>(fldSize_); i++){
		VALUE str;
		if(*iFile_.getVal(i)=='\0'){ str=Qnil; }// nullはQnil
		else { str=str2rbstr(iFile_.getVal(i));}
		rb_ary_store( datas,i,str );
	}

	return datas;

}catch(...){	
	throw;
}

// -----------------------------------------------------------------------------
// HASH格納、GETS
// -----------------------------------------------------------------------------
VALUE mcsvin::getsHash() try 
{
	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return Qnil; }

	// 一行ずつ読み込み
	if ( iFile_.read() == EOF){ return Qnil;	}
	
	VALUE fldHash=rb_hash_new();
	for(int i=0; i<static_cast<int>(fldSize_); i++){
		VALUE str;
		if(*iFile_.getVal(i)=='\0'){ str=Qnil; }// nullはQnil
		else { str=str2rbstr(iFile_.getVal(i));}
		rb_hash_aset(fldHash,str2rbstr(iFile_.fldName(i).c_str()), str );
	}
	
	return fldHash;
	
}catch(...){
	throw;
}

// -----------------------------------------------------------------------------
// Array格納、KEYあり、GETS
// -----------------------------------------------------------------------------
VALUE mcsvin::getsArrayKey() try 
{
	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return rb_ary_new3(3,Qnil,Qnil,Qnil); }

	// キーブレイクフラグ(last,first)
	VALUE keybreakBot_rb;
	VALUE keybreakTop_rb;

	// 一行読み込み
	if ( EOF != iFile_.read() ){ 
		return rb_ary_new3(3,Qnil,Qnil,Qnil); 
	} 

	// 先頭行の場合は再読み込み
	if( iFile_.begin() ){
		kbFlag_=true;
		if ( EOF != iFile_.read() ){ 
			return rb_ary_new3(3,Qnil,Qnil,Qnil); 
		} 
	}
		
	if( kbFlag_ ){ keybreakTop_rb=Qtrue; }
	else         { keybreakTop_rb=Qfalse;}

	if( iFile_.keybreak() ){
		keybreakBot_rb=Qtrue;
		kbFlag_=true;
	}else{
		keybreakBot_rb=Qfalse;
		kbFlag_=false;
	}

	// 項目値配列
	VALUE fldArray=rb_ary_new2(fldSize_);
	for(int i=0; i<static_cast<int>(fldSize_); i++){	
		VALUE str;
		if(*iFile_.getOldVal(i)=='\0') { str=Qnil; } // nullはQnil
		else { str=str2rbstr(iFile_.getOldVal(i)); }
		rb_ary_store( fldArray,i,str );
	}

	// return値配列
	VALUE datas=rb_ary_new2(3);
	rb_ary_store( datas,0,fldArray );
	rb_ary_store( datas,1,keybreakTop_rb );
	rb_ary_store( datas,2,keybreakBot_rb );
	
	return datas;

}catch(...){
	throw;
}

// -----------------------------------------------------------------------------
// HASH格納、KEYあり、GETS
// -----------------------------------------------------------------------------
VALUE mcsvin::getsHashKey() try 
{
	// -nfnで0バイトデータ場合はreturn
	if( nfn() && fldsize()==0 ){ return rb_ary_new3(3,Qnil,Qnil,Qnil); }

	// キーブレイクフラグ(last,first)
	VALUE keybreakBot_rb;
	VALUE keybreakTop_rb;

	// 一行読み込み
	if ( EOF != iFile_.read() ){ 
		return rb_ary_new3(3,Qnil,Qnil,Qnil); 
	} 

	// 先頭行の場合は再読み込み
	if( iFile_.begin() ){
		kbFlag_=true;
		if ( EOF != iFile_.read() ){ 
			return rb_ary_new3(3,Qnil,Qnil,Qnil); 
		} 
	}

	if( kbFlag_ )	{ keybreakTop_rb=Qtrue; }
	else					{ keybreakTop_rb=Qfalse;}

	if( iFile_.keybreak() ){
		keybreakBot_rb=Qtrue;
		kbFlag_=true;
	}else{
		keybreakBot_rb=Qfalse;
		kbFlag_=false;
	}

	VALUE fldHash=rb_hash_new();

	for(int i=0; i<static_cast<int>(fldSize_); i++){
		
		VALUE str;
		if(*iFile_.getOldVal(i)=='\0'){ str=Qnil; } // nullはQnil
		else { str=str2rbstr(iFile_.getOldVal(i));}
		rb_hash_aset( fldHash , str2rbstr( fldName(i)) , str );
	}

	// 項目値の格納
	VALUE datas=rb_ary_new2(3);
	rb_ary_store( datas,0,fldHash );
	rb_ary_store( datas,1,keybreakTop_rb );
	rb_ary_store( datas,2,keybreakBot_rb );

	return datas;

}catch(...){
	throw;
}

// ======================================================================
// GETS
// ======================================================================
VALUE mcsvin::gets() try 
{
	// -nfnの場合は自動的にArray
	if(byArray_ || nfn()){
		if(hasKey_) return getsArrayKey();
		else       	return getsArray();
	}else{
		if(hasKey_) return getsHashKey();
		else        return getsHash();
	}

}catch(...){
	throw;
}

// =============================================================================
// rMmcsvin クラス(mcsvinクラスのrubyラッパ)
//  機能: 1) kgEnvとコマンドライン引数のメモリを確保する
//        2) 正常終了,エラー終了の統一的メソッドを提供する
// =============================================================================
class rMcsvin 
{
private:

	void freeMod() try 
	{
		if(mod!=0){ delete mod; }
		mod=0;	

	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at freeMod()");
	}

public:
	kgEnv env;
	string argstr; // rubyの引数をコピーして格納するための変数
	kgAutoPtr2<char*> argv;
	mcsvin* mod; // 一度実行(RUN)されると0となる．
	VALUE object_;  // rMcsvinオブジェクト(rb_yieldで必要)

	~rMcsvin(){ if(mod!=0) { delete mod;} }

	// ガベージコレクションで終了メソッド
	void gcEnd() try {
		if(mod!=0){
			mod->close();
			freeMod();
		}
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at gcEnd()");
	}

	// エラー終了メソッド
	void errorEnd(kgError& err) try 
	{
		mod->errorEnd(err);
		
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at errorEnd()");
	}

	// 正常終了メソッド
	void successEnd() try 
	{
		mod->successEnd();
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at successEnd()");
	}
};

// =============================================================================
// 公開メソッド
// =============================================================================
// -----------------------------------------------------------------------------
// NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW
//
// def initialize(args,arrayHashFlag)
// 引数の設定(rubyで指定されたargvをkgmodにchar*として渡す)
// -----------------------------------------------------------------------------
VALUE csvin_init(int argc, VALUE *argv, VALUE self) try 
{
	rMcsvin* rmod;
	Data_Get_Struct(self,rMcsvin,rmod);

	try {
	
		// 引数をopetionsにセット
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
			rb_raise(rb_eRuntimeError,"memory allocation error");
		}

		// vv配列0番目はコマンド名
		vv[0]=const_cast<char*>(rmod->mod->name());

		size_t vvSize;
		for(vvSize=0; vvSize<opts.size(); vvSize++){
			vv[vvSize+1] = opts.at(vvSize);
		}
		vvSize+=1;

		// modの初期化&引数の存在チェック
		rmod->mod->init(vvSize, const_cast<const char**>(vv), &rmod->env);
		rmod->mod->args()->paramcheck("i=,k=,s=,-nfn,-array,-q",false);

		// 各種引数の設定 i=、-array、k=
		// k=が指定されていればkgCSVkeyを利用、指定されていなければkgCSVfldを利用する。
		rmod->mod->fsName_ = rmod->mod->args()->toString("i=",false);
		rmod->mod->byArray_ = rmod->mod->args()->toBool("-array");
		rmod->mod->qflg_ = rmod->mod->args()->toBool("-q");
		if(rmod->mod->args()->get(string("k=")).size()==0){
			rmod->mod->hasKey_=false;
		}else{
			rmod->mod->hasKey_=true;
		}
		if(rmod->mod->args()->get(string("s=")).size()==0){
			rmod->mod->hasSkey_=false;
		}else{
			rmod->mod->hasSkey_=true;
		}


		// このタイミングでファイルオープン
		// でないと、newした直後にnamesメソッドが使えない。
		rmod->mod->open();

		// ブロック引数があればyield実行
		if(rb_block_given_p()){
			rb_yield(rmod->object_);
			rmod->successEnd();
		}

	}catch(kgError& err){ // kgmod関係エラーのchatch
		rmod->errorEnd(err); 
		throw;
	}
 	return self;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_init()");
}

// -----------------------------------------------------------------------------
// EACH
// -----------------------------------------------------------------------------
VALUE csvin_each(VALUE self) try 
{
	rMcsvin* rmod;
	Data_Get_Struct(self,rMcsvin,rmod);

	if(rmod->mod == 0){
		rb_raise(rb_eRuntimeError,"`Mcsvin.each' cannot be executed just once");
	}

	try {

		rmod->mod->run();

	}catch(kgError& err){ 
		rmod->errorEnd(err); throw;
	}

	return Qtrue;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_each()");
}

// -----------------------------------------------------------------------------
// GETS 
// -----------------------------------------------------------------------------
VALUE csvin_gets(VALUE self) try 
{
	rMcsvin* rmod;
	Data_Get_Struct(self,rMcsvin,rmod);

	try { 

		return rmod->mod->gets();

	}catch(kgError& err){ 
		rmod->errorEnd(err); throw;
	}
	return Qnil;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_gets()");
}

// -----------------------------------------------------------------------------
// NAMES NAMES NAMES NAMES NAMES NAMES NAMES NAMES NAMES NAMES NAMES NAMES
// -----------------------------------------------------------------------------
/*
 * call-seq:
 * names -> String Array
 *
 *  項目名の配列を返す。
 *
 * === 引数
 * なし
 *
 */
VALUE csvin_names(VALUE self) try 
{
	rMcsvin* rmod;
	Data_Get_Struct(self,rMcsvin,rmod);

	try { 
	
		// 項目名のセット
		if( rmod->mod->nfn() ){
			 return Qnil;
		}else{
			VALUE names = rb_ary_new2(rmod->mod->fldsize());
			for(size_t i=0; i<rmod->mod->fldsize(); i++){
				rb_ary_store( names, i, str2rbstr( rmod->mod->fldName(i) ) );
			}
			return names; 
		}
		
		return Qnil;

	}catch(kgError& err){ 
		rmod->errorEnd(err); throw;
	}

}catch(...){
	rb_raise(rb_eRuntimeError,"at csvin_names()");
}

// -----------------------------------------------------------------------------
// CLOSE 
// closeしてないけどいいの？
// -----------------------------------------------------------------------------
VALUE csvin_close(VALUE self) try 
{
	rMcsvin* rmod;
	Data_Get_Struct(self,rMcsvin,rmod);

	try { 
		rmod->successEnd();

	}catch(kgError& err){ // kgmod関係エラーのchatch
		rmod->errorEnd(err); throw;
	}

	return Qtrue;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_close()");
}

// -----------------------------------------------------------------------------
// メモリ解放
// kgRubyModの領域開放(GC時にrubyにより実行される)(xxx_alloc()にて登録される)
// -----------------------------------------------------------------------------
void csvin_free(rMcsvin* rmod) try 
{
		if(rmod!=0) delete rmod;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_free()");
}

// -----------------------------------------------------------------------------
// インスタンス化される時のメモリ確保
// -----------------------------------------------------------------------------
VALUE mcsvin_alloc(VALUE klass) try 
{
	rMcsvin* rmod=new rMcsvin;
	rmod->mod = new mcsvin;
	VALUE object=Data_Wrap_Struct(klass,0,csvin_free,rmod);
	rmod->object_ = object;
	return object;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at csvin_alloc()");
}

// -----------------------------------------------------------------------------
// ruby Mcsvin クラス init
// -----------------------------------------------------------------------------
void Init_mcsvin(void) 
{
	// モジュール定義:MCMD::xxxxの部分
	VALUE mcmd=rb_define_module("MCMD");

	VALUE mcsvin;
	mcsvin=rb_define_class_under(mcmd,"Mcsvin",rb_cObject);
	rb_define_alloc_func(mcsvin, mcsvin_alloc);
	rb_define_method(mcsvin,"initialize", (VALUE (*)(...))csvin_init ,-1);
	rb_define_method(mcsvin,"each"      , (VALUE (*)(...))csvin_each ,0);
	rb_define_method(mcsvin,"gets"      , (VALUE (*)(...))csvin_gets ,0);
	rb_define_method(mcsvin,"names"     , (VALUE (*)(...))csvin_names,0);
	rb_define_method(mcsvin,"close"     , (VALUE (*)(...))csvin_close,0);
}

