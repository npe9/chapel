/*
 * A simple mini-Chapel parser developed from Shannon's
 * experiments teaching herself flex and bison, and used
 * to exercise a prototype Chapel AST.
 *
 * Brad Chamberlain, 6/2004
 *
 */

%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lexyacc.h"

%}

%start program

%union	{
  bool boolval;
  long intval;
  char* pch;

  unOpType uot;
  binOpType bot;
  getsOpType got;
  varType vt;
  paramType pt;

  Expr* pexpr;
  DomainExpr* pdexpr;
  Stmt* stmt;
  Type* pdt;
  TupleType* tupledt;
  Symbol* psym;
  VarSymbol* pvsym;
  TypeSymbol* ptsym;
  FnSymbol* fnsym;
  ReduceSymbol* redsym;
  ClassSymbol* pcsym;
}


%token CONFIG STATIC
%token VAR CONST

%token DOMAIN
%token INDEX

%token ENUM TYPEDEF CLASS
%token FUNCTION
%token INOUT IN OUT REF VAL

%token IDENT QUERY_IDENT
%token <ptsym> TYPE_IDENT
%token <redsym> REDUCE_IDENT
%token <pcsym> CLASS_IDENT
%token INTLITERAL FLOATLITERAL COMPLEXLITERAL
%token <pch> STRINGLITERAL

%token IF ELSE
%token FOR FORALL IN
%token WHILE DO
%token RETURN

%token BY
%token ELLIPSIS

%token GETS PLUSGETS MINUSGETS TIMESGETS DIVGETS BITANDGETS BITORGETS 
%token BITXORGETS BITSLGETS BITSRGETS

%token DIM REDUCE

%token EQUALS NEQUALS LEQUALS GEQUALS NEQUALS GTHAN LTHAN
%token LOGOR LOGAND
%token BITOR BITAND BITXOR BITSL BITSR
%token EXP


%type <boolval> varconst
%type <intval> intliteral

%type <got> assignOp
%type <bot> otherbinop
/*%type <uot> unop*/
%type <vt> vardecltag
%type <pt> formaltag

%type <pdt> type domainType indexType arrayType tupleType
%type <tupledt> tupleTypes
%type <pdt> vardecltype fnrettype
%type <pch> identifier query_identifier
%type <psym> identsym enumList formal nonemptyformals formals idlist indexlist
%type <pcsym> subclass
%type <pexpr> simple_lvalue assign_lvalue lvalue atom expr exprlist nonemptyExprlist literal range
%type <pexpr> reduction vardeclinit reduceDim
%type <pdexpr> domainExpr
%type <stmt> program statements statement decl vardecl assignment conditional
%type <stmt> retStmt loop forloop whileloop enumdecl typealias typedecl fndecl
%type <stmt> classdecl


/* These are declared in increasing order of precedence. */

%left LOGOR
%left LOGAND
%right '!'
%left EQUALS NEQUALS
%left LTHAN LEQUALS GTHAN GEQUALS
%left BITSL BITSR
%left BITOR
%left BITXOR
%left BITAND
%left '+' '-'
%left '*' '/' '%'
%right TUMINUS TUPLUS
%right '~'
%right EXP
%left TBY
%left ':'

%% 


program:  
  statements
    { yystmtlist = $$; }
;


vardecltag:
  /* nothing */
    { $$ = VAR_NORMAL; }
| CONFIG
    { $$ = VAR_CONFIG; }
| STATIC
    { $$ = VAR_STATE; }
;


varconst:
  VAR
    { $$ = false; }
| CONST
    { $$ = true; }
;


identsym:
  identifier
    { $$ = new Symbol(SYMBOL, $1); }
;


idlist:
  identsym
| idlist ',' identsym
    {
      $1->append($3);
      $$ = $1;
    }
;


vardecltype:
  /* nothing */
    { $$ = dtUnknown; }
| ':' type
    { $$ = $2; }
;


vardeclinit:
  /* nothing */
    { $$ = nilExpr; }
| GETS expr
    { $$ = $2; }
;


vardecl:
  vardecltag varconst idlist vardecltype vardeclinit ';'
    { $$ = Symboltable::defineVarDefStmt($3, $4, $5, $1, $2); }
;


typedecl:
  typealias
| enumdecl
| classdecl
;


typealias:
  TYPEDEF identifier ':' type ';'
    { $$ = Symboltable::defineUserType($2, $4); }
| TYPEDEF identifier ':' type GETS expr ';'
    { $$ = Symboltable::defineUserType($2, $4, $6); }
;


enumdecl:
  ENUM identifier GETS enumList ';'
    {
      EnumSymbol* enumlist = Symboltable::defineEnumList($4);      
      EnumType* pdt = new EnumType(enumlist);
      Symbol* pst = new TypeSymbol($2, pdt);
      pdt->addName(pst);
      Symboltable::define(pst);
      $$ = new TypeDefStmt(pdt);
    }
;


subclass:
  /* nothing */
    { $$ = nilClassSymbol; }
| ':' identifier
    {
      $$ = Symboltable::lookupClass($2);
    }
;


classdecl:
  CLASS identifier subclass '{'
    {
      $<pcsym>$ = Symboltable::startClassDef($2, $3);
    }
                                statements '}'
    {
      $$ = Symboltable::finishClassDef($<pcsym>5, $6);
    }
;


enumList:
  identsym
| enumList BITOR identsym
    {
      $1->append($3);
      $$ = $1;
    }
;


formaltag:
  /* nothing */
    { $$ = PARAM_INOUT; }
| IN
    { $$ = PARAM_IN; }
| INOUT
    { $$ = PARAM_INOUT; }
| OUT
    { $$ = PARAM_OUT; }
| CONST
    { $$ = PARAM_CONST; }
| REF
    { $$ = PARAM_INOUT; }
| VAL
    { $$ = PARAM_IN; }
;


formal:
  formaltag idlist vardecltype
    { $$ = Symboltable::defineParams($1, $2, $3); }
;


nonemptyformals:
  formal
| nonemptyformals ';' formal
    {
      $1->append($3);
      $$ = $1;
    }
;

formals:
  /* empty */
    { $$ = nilSymbol; }
| nonemptyformals
;


fnrettype:
  /* empty */
    { $$ = dtVoid; }
| ':'
    { $$ = dtUnknown; }
| ':' type
    { $$ = $2; }
;


fndecl:
  FUNCTION identifier
    {
      $<fnsym>$ = Symboltable::startFnDef($2);
    }
                      '(' formals ')' fnrettype statement
    {
      $$ = Symboltable::finishFnDef($<fnsym>3, $5, $7, $8);
    }
;


decl:
  vardecl
| typedecl
| fndecl
;


tupleTypes:
  type
    { $$ = new TupleType($1); }
| tupleTypes ',' type
    { 
      $1->addType($3);
      $$ = $1;
    }
;


tupleType:
  '(' tupleTypes ')'
    { $$ = $2; }
;


type:
  domainType
| indexType
| arrayType
| tupleType
| TYPE_IDENT
    { $$ = $1->type; }
| CLASS_IDENT
    { $$ = $1->type; }
| query_identifier
    { $$ = dtUnknown; }
;

domainType:
  DOMAIN
    { $$ = new DomainType(); }
| DOMAIN '(' expr ')'
    { $$ = new DomainType($3); }
;


indexType:
  INDEX
    { $$ = new IndexType(); }
| INDEX '(' expr ')'
    { $$ = new IndexType($3); }
;


arrayType:
  '[' ']' type
    { $$ = new ArrayType(unknownDomain, $3); }
| '[' query_identifier ']' type
    { 
      Symboltable::defineQueryDomain($2);  // really need to tuck this into
                                           // a var def stmt to be inserted
                                           // as soon as the next stmt is
                                           // defined  -- BLC
      $$ = new ArrayType(unknownDomain, $4);
    }
| '[' domainExpr ']' type
    { $$ = new ArrayType($2, $4); }
;


statements:
  /* empty */
    { $$ = nilStmt; }
| statements statement
    { $$ = appendLink($1, $2); }
;


statement:
  ';'
    { $$ = new NoOpStmt(); }
| decl
| assignment
| conditional
| loop
| simple_lvalue ';'  /* This used to be "expr." Isn't this just for function calls? -SJD */
    { $$ = new ExprStmt($1); }
| retStmt
| '{'
    { Symboltable::startCompoundStmt(); }
      statements '}'
    { $$ = Symboltable::finishCompoundStmt($3); }
| error
    { printf("syntax error"); exit(1); }
;


retStmt:
  RETURN ';'
    { $$ = new ReturnStmt(nilExpr); }
| RETURN expr ';'
    { $$ = new ReturnStmt($2); }
;


fortype:
  FOR
| FORALL
;


indexlist:
  idlist
| '(' idlist ')'
  { $$ = $2; }
;


forloop:
  fortype indexlist IN expr
    { 
      $<pvsym>$ = Symboltable::startForLoop($2);
    }
                                 statement
    { 
      $$ = Symboltable::finishForLoop(true, $<pvsym>5, $4, $6);
    }
;


whileloop:
  WHILE expr statement
    { $$ = new WhileLoopStmt(true, $2, $3); }
| DO statement WHILE expr ';'
    { $$ = new WhileLoopStmt(false, $4, $2); }
;


loop:
  forloop
| whileloop
;


conditional:
  IF expr statement
    { $$ = new CondStmt($2, $3); }
| IF expr statement ELSE statement
    { $$ = new CondStmt($2, $3, $5); }
;


assignOp:
  GETS
    { $$ = GETS_NORM; }
| PLUSGETS
    { $$ = GETS_PLUS; }
| MINUSGETS
    { $$ = GETS_MINUS; }
| TIMESGETS
    { $$ = GETS_MULT; }
| DIVGETS
    { $$ = GETS_DIV; }
| BITANDGETS
    { $$ = GETS_BITAND; }
| BITORGETS
    { $$ = GETS_BITOR; }
| BITXORGETS
    { $$ = GETS_BITXOR; }
| BITSLGETS
    { $$ = GETS_BITSL; }
| BITSRGETS
    { $$ = GETS_BITSR; }
;


assign_lvalue:
  lvalue
| '[' domainExpr ']' lvalue
  {
    $2->setForallExpr($4);
    $$ = $2;
  }
;


assignment:
  assign_lvalue assignOp expr ';'
    { $$ = new ExprStmt(new AssignOp($2, $1, $3)); }
;


exprlist:
  /* empty */
    { $$ = nilExpr; }
| nonemptyExprlist
;


nonemptyExprlist:
  expr
| nonemptyExprlist ',' expr
    { $1->append($3); }
;


simple_lvalue:
  identifier
    { $$ = new Variable(Symboltable::lookup($1)); }
| simple_lvalue '.' identifier
    { $$ = Symboltable::defineMemberAccess($1, $3); }
| simple_lvalue '(' exprlist ')'
    { $$ = ParenOpExpr::classify($1, $3); }
/*
| simple_lvalue '[' exprlist ']'
    { $$ = ParenOpExpr::classify($1, $3); }
*/
;


lvalue:
  simple_lvalue
;


atom:
  literal
| lvalue
;


expr: 
  atom
| reduction
| expr ':' type
    { $$ = new CastExpr($3, $1); }
| range
| '(' nonemptyExprlist ')' 
    { 
      if ($2->next->isNull()) {
        $$ = $2;
      } else {
        $$ = new Tuple($2);
      }
    }
| '[' domainExpr ']'
    { $$ = $2; }
| '[' domainExpr ']' expr
    {
      $2->setForallExpr($4);
      $$ = $2;
    }
| '+' expr                                     %prec TUPLUS
    { $$ = new UnOp(UNOP_PLUS, $2); }
| '-' expr                                     %prec TUMINUS
    { $$ = new UnOp(UNOP_MINUS, $2); }
| '!' expr
    { $$ = new UnOp(UNOP_LOGNOT, $2); }
| '~' expr
    { $$ = new UnOp(UNOP_BITNOT, $2); }
| expr '+' expr
    { $$ = Expr::newPlusMinus(BINOP_PLUS, $1, $3); }
| expr '-' expr
    { $$ = Expr::newPlusMinus(BINOP_MINUS, $1, $3); }
| expr '*' expr
    { $$ = new BinOp(BINOP_MULT, $1, $3); }
| expr '/' expr
    { $$ = new BinOp(BINOP_DIV, $1, $3); }
| expr '%' expr
    { $$ = new BinOp(BINOP_MOD, $1, $3); }
| expr EQUALS expr
    { $$ = new BinOp(BINOP_EQUAL, $1, $3); }
| expr NEQUALS expr
    { $$ = new BinOp(BINOP_NEQUAL, $1, $3); }
| expr LEQUALS expr
    { $$ = new BinOp(BINOP_LEQUAL, $1, $3); }
| expr GEQUALS expr
    { $$ = new BinOp(BINOP_GEQUAL, $1, $3); }
| expr GTHAN expr
    { $$ = new BinOp(BINOP_GTHAN, $1, $3); }
| expr LTHAN expr
    { $$ = new BinOp(BINOP_LTHAN, $1, $3); }
| expr BITAND expr
    { $$ = new BinOp(BINOP_BITAND, $1, $3); }
| expr BITOR expr
    { $$ = new BinOp(BINOP_BITOR, $1, $3); }
| expr BITXOR expr
    { $$ = new BinOp(BINOP_BITXOR, $1, $3); }
| expr BITSL expr
    { $$ = new BinOp(BINOP_BITSL, $1, $3); }
| expr BITSR expr
    { $$ = new BinOp(BINOP_BITSR, $1, $3); }
| expr LOGAND expr
    { $$ = new BinOp(BINOP_LOGAND, $1, $3); }
| expr LOGOR expr
    { $$ = new BinOp(BINOP_LOGOR, $1, $3); }
| expr EXP expr
    { $$ = new BinOp(BINOP_EXP, $1, $3); }

/** Can "by" really apply to arbitrary expressions or just ranges and reductions? -SJD */

| expr otherbinop expr                           %prec TBY
    { $$ = new SpecialBinOp($2, $1, $3); }
;


reduceDim:
  /* empty */
    { $$ = nilExpr; }
| '(' expr ')'
    { $$ = $2; }
| '(' DIM GETS expr ')'
    { $$ = $4; }
;


reduction:
  REDUCE_IDENT reduceDim expr
    { $$ = new ReduceExpr($1, $2, $3); }
| REDUCE reduceDim BY REDUCE_IDENT expr
    { $$ = new ReduceExpr($4, $2, $5); }
;


/* Here are the other three reduce/reduce errors! nonemptyExprlist and indexlist -SJD */
domainExpr:
  nonemptyExprlist
    { $$ = new DomainExpr($1); }
| indexlist IN nonemptyExprlist          // BLC: This is wrong vv
    { $$ = new DomainExpr($3, Symboltable::defineVars($1, dtInteger)); }
;


range:
  expr ELLIPSIS expr
    { $$ = new SimpleSeqExpr($1, $3); }
| expr ELLIPSIS expr BY expr
    { $$ = new SimpleSeqExpr($1, $3, $5); }
| '*'
    { $$ = new FloodExpr(); }
| ELLIPSIS
    { $$ = new CompleteDimExpr(); }
;


literal:
  intliteral
    { $$ = new IntLiteral(yytext, $1); }
| FLOATLITERAL
    { $$ = new FloatLiteral(yytext, atof(yytext)); }
| COMPLEXLITERAL
    { $$ = new ComplexLiteral(yytext, atof(yytext)); }
| STRINGLITERAL
    { $$ = new StringLiteral($1); }
;


intliteral:
  INTLITERAL
    { $$ = atol(yytext); }
;


otherbinop:
  BY
    { $$ = BINOP_BY; }
;


identifier:
  IDENT
    { $$ = copystring(yytext); }
| CLASS_IDENT
    { $$ = $1->name; }
;


query_identifier:
  QUERY_IDENT
    { $$ = copystring(yytext+1); }
;


%%
