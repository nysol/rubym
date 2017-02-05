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
// mtable.cpp csv => 行列 クラス
// =============================================================================
#include <sstream>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <ruby.h>
#include <kgmod.h>
#include <kgMethod.h>


#define BUFSIZE 102400

using namespace std;
using namespace kglib;

extern "C" {
	void Init_mtable(void);
}

// -----------------------------------------------------------------------------
// encodingを考慮した文字列生成
// -----------------------------------------------------------------------------
static VALUE str2rbstr(const char *ptr)
{
	// rb_external_str_new_cstrが定義されているばそちらを使う
	#if defined(rb_external_str_new_cstr)
		return rb_external_str_new_cstr(ptr);
	#else
		return rb_str_new2(ptr);
	#endif

}

// =============================================================================
// mtable クラス
//   CSVファイルをメモリに読み込み，行と列の指定で自由にcell情報をセットする
//   ためのkgMod継承クラス．
// =============================================================================
class mtable : public kgMod 
{
	kgAutoPtr2<char*> _nameStr_ap;
	kgAutoPtr2<char*> _valStr_ap;

	char* _buf; 		// 全データを格納するバッファ
	int   _blocks;  // read回数。
	vector<char*> _cell;  		// 全セルへのインデックス
	string  _fsName; 			// i=
	bool         _fldNameNo; 	// -nfn
	char** 			 _nameStr;		// 項目名一覧
	size_t 			 _fldSize;    // 項目数
	size_t       _recSize;    // 行数  

public:

	mtable(void){ // コンストラクタ
		_name    = "mtable";
		_version = "1.0";
		_blocks  = 0;
		_fldSize = 0;
		_recSize = 0;
	};
	virtual ~mtable() {}
	//アクセッサ
	void   fname(string fn)	{ _fsName = fn ;}
	void   nfn(bool nfnf)					{ _fldNameNo = nfnf ;}
	bool   nfn(void)							{ return _fldNameNo;}
	char*  header(size_t i)				{ return *(_nameStr+i);}
	size_t fldsize()							{ return _fldSize;}
	size_t recsize()							{ return _recSize;}

	int run();

	char* cell(size_t col, size_t row){
		return _cell.at(row*_fldSize+col);
	}
};

// -----------------------------------------------------------------------------
//  run
// -----------------------------------------------------------------------------
int mtable::run() try 
{
	// ファイルオープン
	int fd = ::open(_fsName.c_str(), O_RDONLY );
	if(fd == -1 ){
		rb_raise(rb_eRuntimeError,"file open error");
	}

	// 全行読み込む
	size_t totalSize=0;
	_buf=0;
	while(true){
		_blocks++;
		long rbufSz =  BUFSIZE*_blocks+1;
		if(rbufSz <long(0)){
			rb_raise(rb_eRuntimeError,"read buffer is full"); 
		}
		REALLOC_N(_buf, char, rbufSz); // +1は最終行に改行がなかった場合の終端'\0'用
		size_t rsize = ::read(fd, _buf+(BUFSIZE*(_blocks-1)), BUFSIZE);
		if(rsize==0) break;
		totalSize+=rsize;
	}
	::close(fd);

	// bufferの終端位置
	char* endPos=_buf+totalSize;

	if(totalSize==0){
		_fldSize = 0;
		_recSize = 0;
		return 	0;
	}
	if(*(endPos-1)!='\n' && *(endPos-1)!='\r'){
		*endPos='\n';
		totalSize++;
		endPos++;
	} 

	// 項目数のカウント
	_fldSize = kglib::cntFldToken(_buf, totalSize);

	// 項目名(先頭rec)の取得
	char* pnt = _buf;
	
	// １行目が項目名行の場合, 項目名のtoken分割
	if(!nfn()){  		
		_nameStr_ap.set( new char*[_fldSize] );
		_nameStr = _nameStr_ap.get();
		pnt = sepFldToken(_nameStr, _fldSize , pnt , totalSize)+1;
		for(size_t i=0; i<_fldSize;i++){
			splitToken(_nameStr[i],'%'); // 項目名 % チェック
		}
	}
	
	// 項目値char*へのインデックス
	_valStr_ap.set( new char*[_fldSize] );
	char ** valStr = _valStr_ap.get();
	
	while(pnt < endPos){
		pnt = sepFldToken(valStr, _fldSize, pnt , endPos-pnt) + 1;
		_recSize++;
		for(size_t i=0; i < _fldSize; i++){
			_cell.push_back( *(valStr+i) );
		}
	}
	return 0;
}catch(kgError& err){
	ostringstream ss;
	ss << "Error in processing line " << _recSize+1 <<  "(not including header line)";
	err.addMessage(ss.str());
	throw;
}catch(...){
	ostringstream ss;
	ss << "Internal error in processing line" << _recSize+1 <<  "(not including header line)";
	throw kgError(ss.str());
}

// =============================================================================
// rMmtable クラス(mtableクラスのrubyラッパ)
//  機能: 1) kgEnvとコマンドライン引数のメモリを確保する
//        2) 正常終了,エラー終了の統一的メソッドを提供する
// =============================================================================
class rMtable 
{
public:
	kgEnv env;
	string argstr; // rubyの引数をコピーして格納するための変数
	kgAutoPtr2<char*> argv;
	mtable* mod;      // 一度実行(RUN)されると0となる．
	VALUE object_;  // rMtableオブジェクト(rb_yieldで必要)

private:
	void freeMod() try 
	{
		if(mod!=0){ delete mod; }
		mod=0;	
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at freeMod()");
	}

public:

	// エラー終了メソッド
	void errorEnd(kgError& err) try 
	{
		mod->errorEnd(err);
		freeMod();
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at errorEnd()");
	}

	// 正常終了メソッド
	void successEnd() try 
	{
		mod->successEnd();
		freeMod();
	}catch(...){
		rb_raise(rb_eRuntimeError,"Error at successEnd()");
	}
};

// =============================================================================
// 公開メソッド
// =============================================================================
//
// NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW
//
/*
 * call-seq:
 * Mtable.new -> tbl
 *
 * <b>説明</b> テーブルクラスのインスタンスを生成する．この段階ではファイルはまだ読み込まれない．runメソッドを実行して初めて読み込まれる．
 *
 * <b>書式</b> Mtable.new("i=CSVファイル名 [-nfn]")
 *
 * i=:: 読み込むCSVファイル名を指定する．
 *
 * -nfn=::1 行目を項目名と見なさない
 *
 */
VALUE mtable_init(int argc, VALUE *argv, VALUE self) try 
{
	rMtable* rmod;
	Data_Get_Struct(self,rMtable,rmod);

	try 
	{ 
		// 引数セット
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
		rmod->mod->args()->paramcheck("i=,-nfn",false);

		// 各種引数の設定 i=,-nfn
		rmod->mod->fname(rmod->mod->args()->toString("i=",false));
    rmod->mod->nfn(rmod->mod->args()->toBool("-nfn"));

		// メモリにローディング
		rmod->mod->run();

		// ブロック引数があればyield実行
		if(rb_block_given_p()){
			rb_yield(rmod->object_);
			rmod->successEnd();
		}

	}catch(kgError& err){
		rmod->errorEnd(err); throw;
	}
	return self;

}catch(...){
	rb_raise(rb_eRuntimeError,"Error at mtable_init()");
}

// -----------------------------------------------------------------------------
// NAMES 
// -----------------------------------------------------------------------------
/*
 * call-seq:
 * names -> String Array or nil
 *
 *  項目名配列を返す。
 *
 * === 引数
 * なし
 *
 */
VALUE mtable_names(VALUE self) try 
{
	rMtable* rmod;
	Data_Get_Struct(self,rMtable,rmod);
	VALUE rtn; 
	if (rmod->mod->nfn()){
		rtn = Qnil;
	}else{
		rtn = rb_ary_new2(rmod->mod->fldsize());
		for(size_t i=0 ;i<rmod->mod->fldsize(); i++){
			rb_ary_store( rtn, i, str2rbstr( rmod->mod->header(i) ) );
		}
	}
  return rtn;

}catch(...){
  rb_raise(rb_eRuntimeError,"Error at mtable_names()");
}

// -----------------------------------------------------------------------------
// NAME2NUM 
// -----------------------------------------------------------------------------
/*
 * call-seq:
 * name2num -> String=>Fixnum Hash or nil
 *
 *  項目名をキー、対応する項目番号を値とする Hash を返す。
 *
 * === 引数
 * なし
 *
 */
VALUE mtable_name2num(VALUE self) try 
{
	rMtable* rmod;
	Data_Get_Struct(self,rMtable,rmod);
	VALUE rtn; 
	if (rmod->mod->nfn()){
		rtn = Qnil;
	}else{
		rtn =rb_hash_new();
		for(size_t i=0 ;i<rmod->mod->fldsize(); i++){
			rb_hash_aset(rtn, str2rbstr( rmod->mod->header(i) ) , INT2FIX(i));
		}
	}
  return rtn;

}catch(...){
  rb_raise(rb_eRuntimeError,"Error at mtable_names()");
}

// -----------------------------------------------------------------------------
// SIZE 
// -----------------------------------------------------------------------------
/*
 * call-seq:
 * size -> Fixnum
 *
 *  行数を返す。
 *
 * === 引数
 * なし
 *
 */
VALUE mtable_size(VALUE self) try {
	rMtable* rmod;
	Data_Get_Struct(self,rMtable,rmod);
  return INT2FIX(rmod->mod->recsize());
}catch(...){
  rb_raise(rb_eRuntimeError,"Error at mtable_size()");
}

// -----------------------------------------------------------------------------
// CELL 
// -----------------------------------------------------------------------------
/*
 * call-seq:
 * cell -> String
 *
 * row(行),col(列) に対応するセルの値を返す。
 * row,col の与え方は、列番号と行番号による。
 * 列/行番号共に 0 か ら始まる整数 (Mcsvin の列番号は 1 から始まる)。
 * row,col が範囲外の場合は nil を返す。
 * row	行番号で、0 以上の整数を用いる。デフォルトは 0。
 * col	列番号で、0 以上の整数を用いる。項目名は指定できない。デフォルトは 0。 
 * col のみ与えると 0 行目の col 番目の項目の値を返す。
 * cell(col,0) を指定したのと同等。
 * また col,row 両方とも与えなければ 0 行目の 0 項目目の値を返す。
 * cell(0,0) を指定したのと同等。
 * === 引数
 *  col 列
 *  row 行
 */
VALUE mtable_cell(int argc, VALUE *argv, VALUE self) try {
	rMtable* rmod;
	Data_Get_Struct(self,rMtable,rmod);

	VALUE option;
	rb_scan_args(argc, argv,"*",&option);

	size_t colNo=0;
	size_t rowNo=0;

	if(argc==1){
		// 列番号
    VALUE v1=RARRAY_PTR(option)[0];
		if( TYPE(v1) == T_FIXNUM ){
			colNo = FIX2INT(v1);
		}else if( TYPE(v1) == T_BIGNUM ){
			colNo = NUM2INT(v1);
		}else{
			rb_raise(rb_eRuntimeError,"argument type error (1st argument must be a number");
		}

	}else if(argc==2){

		// 列番号
    VALUE v1=RARRAY_PTR(option)[0];
		if( TYPE(v1) == T_FIXNUM ){
			colNo = FIX2INT(v1);
		}else if( TYPE(v1) == T_BIGNUM ){
			colNo = NUM2INT(v1);
		}else{
			rb_raise(rb_eRuntimeError,"argument type error (1st argument must be a number");
		}

		// 行番号
    VALUE v2=RARRAY_PTR(option)[1];
		if( TYPE(v2) == T_FIXNUM ){
			rowNo = FIX2INT(v2);
		}else if( TYPE(v2) == T_BIGNUM ){
			rowNo = NUM2INT(v2);
		}else{
			rb_raise(rb_eRuntimeError,"argument type error (1st argument must be a number");
		}
	}

	// 範囲チェック
	if(colNo>=rmod->mod->fldsize()){
		rb_raise(rb_eRuntimeError,"col number must be less than %zd",rmod->mod->fldsize());
	}
	if(rowNo>=rmod->mod->recsize()){
		rb_raise(rb_eRuntimeError,"row number must be less than %zd",rmod->mod->recsize());
	}

	// 値を返す
	return str2rbstr( rmod->mod->cell(colNo, rowNo) );


}catch(...){
  rb_raise(rb_eRuntimeError,"Error at mtable_records()");
}

// -----------------------------------------------------------------------------
// メモリ解放
// kgRubyModの領域開放(GC時にrubyにより実行される)(xxx_alloc()にて登録される)
// -----------------------------------------------------------------------------
void mtable_free(rMtable* rmod) try 
{
	if(rmod!=0){ delete rmod; }
	
}catch(...){
	rb_raise(rb_eRuntimeError,"Error at mtable_free()");
}

// -----------------------------------------------------------------------------
// インスタンス化される時のメモリ確保
// -----------------------------------------------------------------------------
VALUE mtable_alloc(VALUE klass) try 
{
	rMtable* rmod=new rMtable;
	rmod->mod = new mtable;
	VALUE object=Data_Wrap_Struct(klass,0,mtable_free,rmod);
	rmod->object_ = object;
	return object;
	
}catch(...){
	rb_raise(rb_eRuntimeError,"Error at table_alloc()");
}

// -----------------------------------------------------------------------------
// ruby Mtable クラス init
// -----------------------------------------------------------------------------
/*
 * = 指定した CSV データ全体をメモリに読み込んで処理するクラス以下のような特徴を持つ。
 *   行と列の指定によりセルをランダムにアクセス可能。
 *   読み込み専用であり、データの更新や追加は一切できない。 
 *   データは全て文字列として読み込むので、その他の方で利用する時は適宜型変換 (ex. to i) が必要。 
 *   メモリが空いている限りデータを読み込む。領域がなくなればエラー終了する。 
 * === 利用例1
 *   # dat1.csv 
 *   customer,date,amount 
 *   A,20081201,10
 *   B,20081002,40
 *
 *   tbl=Mtable.new("i=dat1.csv")
 *   p tbl.names       # -> ["customer", "date", "amount"]
 *   p tbl.name2num    # -> {"amount"=>2, "date"=>1, "customer"=>0}
 *   p tbl.size        # -> 2
 *   p tbl.cell(0,0)   # -> "A"
 *   p tbl.cell(0,1)   # -> "B"
 *   p tbl.cell(1,1)   # -> "20081202"
 *   p tbl.cell(1)     # -> "20081201"
 *   p tbl.cell        # -> "A"
 * === 利用例2
 *   # dat1.csv 
 *   customer,date,amount 
 *   A,20081201,10
 *   B,20081002,40
 *
 *   tbl=Mtable.new("i=dat1.csv -nfn") # 一行目もデータと見なす。
 *   p tbl.names       # -> nil
 *   p tbl.name2num    # -> nil
 *   p tbl.size        # -> 3
 *   p tbl.cell(0,0)   # -> "customer"
 *   p tbl.cell(0,1)   # -> "A"
 *   p tbl.cell(1,1)   # -> "20081201"
 *   p tbl.cell(1)     # -> "date"
 *   p tbl.cell        # -> "customer"
 */
void Init_mtable(void) 
{
	// モジュール定義:MCMD::xxxxの部分
	VALUE mcmd=rb_define_module("MCMD");

	VALUE mtable;
	mtable=rb_define_class_under(mcmd,"Mtable",rb_cObject);
	rb_define_alloc_func(mtable, mtable_alloc);
	rb_define_method(mtable,"initialize", (VALUE (*)(...))mtable_init    , -1);
	rb_define_method(mtable,"names"     , (VALUE (*)(...))mtable_names   ,  0);
	rb_define_method(mtable,"name2num"  , (VALUE (*)(...))mtable_name2num,  0);
	rb_define_method(mtable,"cell"      , (VALUE (*)(...))mtable_cell    , -1);
	rb_define_method(mtable,"size"      , (VALUE (*)(...))mtable_size    ,  0);
}

