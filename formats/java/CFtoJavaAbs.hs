{-
    BNF Converter: Java Abstract Syntax
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- 
   **************************************************************
    BNF Converter Module

    Description   : This module generates the Java Abstract Syntax
                    It uses the NamedVariables module for variable
                    naming. It returns a list of file names, and the
                    contents to be written into that file. (In Java
                    public classes must go in their own file.)
                    
                    The generated classes also support the Visitor
                    Design Pattern.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 24 April, 2003                           

    Modified      : 2 September, 2003                          

   
   ************************************************************** 
-}

module CFtoJavaAbs (cf2JavaAbs) where

import CF
import Utils((+++),(++++))
import NamedVariables hiding (IVar, getVars, varName)
import List
import Char(toLower)

--Produces abstract data types in Java.
--These follow Appel's "non-object oriented" version.
--They also allow users to use the Visitor design pattern.

type IVar = (String, Int, String)
--The type of an instance variable
--a # unique to that type
--and an optional name (handles typedefs).

--The result is a list of files which must be written to disk.
--The tuple is (FileName, FileContents)
cf2JavaAbs :: String -> String -> CF -> [(FilePath, String)]
cf2JavaAbs packageBase packageAbsyn cf =
    concat (map (prData header packageBase user) (cf2dataLists cf))
 where
  header = "package " ++ packageAbsyn ++ "; // Java Package generated by the BNF Converter.\n"
  user = [n | (n,_) <- tokenPragmas cf]

--Generates a (possibly abstract) category class, and classes for all its rules.
prData :: String -> String -> [UserDef] -> Data ->[(String, String)]
prData header name user (cat, rules) =
  (identCat cat, header ++++
  "public abstract class" +++ (identCat cat) +++ "implements" +++ name ++ ".Visitable {}\n") :
  prRules header name user cat rules --don't use map because some will be Nil
 where
  prRules h n u c [] = []  --this is basically a map which excludes Nil values.
  prRules h n u c (f:fs) = case res of
    ("","") -> prRules h n u c fs
    z -> res : (prRules h n u c fs)
   where res = prRule h n u c f

--Generates classes for a rule, depending on what type of rule it is.
prRule h name user c (fun, cats) = 
    if isNilFun fun || isOneFun fun
    then ("","")  --these are not represented in the AbSyn
    else if isConsFun fun
    then (fun', --this is the linked list case.
    unlines
    [
     h,
     "public class" +++ fun' +++ "implements"+++ name ++ ".Visitable",
     "{",
     (prInstVars vs),
     prConstructor fun' user vs cats,
     prListFuncs fun',
     prAccept name fun', 
     "}"
    ])
    else (fun, --a standard rule
    unlines
    [
     h,
     "public class" +++ fun +++ ext +++ "implements"+++ name ++ ".Visitable",
     "{",
     (prInstVars vs),
     prConstructor fun user vs cats,
     prAccept name fun,
     "}\n"
    ])
   where 
     vs = getVars cats user
     fun' = identCat (normCat c)
     --This handles the case where a LBNF label is the same as the category.
     ext = if fun == c then "" else "extends" +++ (identCat c)

--These are all built-in list functions.
--Later we could include things like lookup,insert,delete,etc.
prListFuncs :: String -> String
prListFuncs c = unlines
 [
  "  public" +++ c +++ "reverse()",
  "  {",
  "    if (" ++ v +++ "== null) return this;",
  "    else",
  "    {",
  "      " ++ c ++ " tmp =" +++ v ++ ".reverse(this);",
  "      " ++ v +++ "= null;",
  "      return tmp;",
  "    }",
  "  }",
  "  public" +++ c +++ "reverse(" ++ c +++ "prev)",
  "  {",
  "    if (" ++ v +++ "== null)",
  "    {",
  "      " ++ v +++ "= prev;",
  "      return this;",
  "    }",
  "    else",
  "    {",
  "      " ++ c +++ "tmp =" +++ v ++ ".reverse(this);",
  "      " ++ v +++ "= prev;",
  "      return tmp;",
  "    }",
  "  }"
 ]
 where
   v = (map toLower c) ++ "_"

--The standard accept function for the Visitor pattern
prAccept :: String -> String -> String
prAccept pack ty = 
  "\n  public void accept(" ++ pack ++ ".Visitor v) { v.visit" ++ ty ++ "(this); }"

--A class's instance variables.
prInstVars :: [IVar] -> String
prInstVars [] = []
prInstVars vars@((t,n,nm):vs) = 
  "  public" +++ t +++ uniques ++ ";" ++++
  (prInstVars vs')
 where
   (uniques, vs') = prUniques t vars
   --these functions group the types together nicely
   prUniques :: String -> [IVar] -> (String, [IVar])
   prUniques t vs = (prVars (findIndices (\x -> case x of (y,_,_) ->  y == t) vs) vs, remType t vs)
   prVars (x:[]) vs =  case vs !! x of
   			(t,n,nm) -> ((varName t nm) ++ (showNum n))
   prVars (x:xs) vs = case vs !! x of 
   			(t,n,nm) -> ((varName t nm) ++ (showNum n)) ++ "," +++
				 (prVars xs vs)
   remType :: String -> [IVar] -> [IVar]
   remType _ [] = []
   remType t ((t2,n,nm):ts) = if t == t2 
   				then (remType t ts) 
				else (t2,n,nm) : (remType t ts)

--The constructor just assigns the parameters to the corresponding instance variables.
prConstructor :: String -> [UserDef] -> [IVar] -> [Cat] -> String
prConstructor c u vs cats = 
  "  public" +++ c ++"(" ++ (interleave types params) ++ ")" +++ "{" +++ 
   prAssigns vs params ++ "}"
  where
   (types, params) = unzip (prParams cats u (length cats) ((length cats)+1))
   interleave _ [] = []
   interleave (x:[]) (y:[]) = x +++ y
   interleave (x:xs) (y:ys) = x +++ y ++ "," +++ (interleave xs ys)

--Prints the parameters to the constructors.   
prParams :: [Cat] -> [UserDef] -> Int -> Int -> [(String,String)]
prParams [] _ _ _ = []
prParams (c:cs) u n m = (identCat c',"p" ++ (show (m-n)))
			: (prParams cs u (n-1) m)
     where
      c' = typename c u
      
--This algorithm peeks ahead in the list so we don't use map or fold
prAssigns :: [IVar] -> [String] -> String
prAssigns [] _ = []
prAssigns _ [] = []
prAssigns ((t,n,nm):vs) (p:ps) =
 if n == 1 then
  case findIndices (\x -> case x of (l,r,_) -> l == t) vs of
    [] -> (varName t nm) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)
    z -> ((varName t nm) ++ (showNum n)) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)
 else ((varName t nm) ++ (showNum n)) +++ "=" +++ p ++ ";" +++ (prAssigns vs ps)

--Different than the standard NamedVariables version because of the user-defined
--types.
getVars :: [Cat] -> [UserDef] -> [IVar]
getVars cs user = foldl (addVar user) [] (map identCat cs)
 where
  addVar user vs c = addVar' vs user 0 c
  addVar' [] u n c = [(c', n, nm)]
   where
    c' = typename c user
    nm = if c == c' then "" else c
  addVar' (i@(t,x,nm):is) u n c = 
    if c == t || c == nm
      then if x == 0
        then (t, 1, nm) : (addVar' is u 2 c)
	else i : (addVar' is u (x+1) c)
      else i : (addVar' is u n c)


varName c s = (map toLower c') ++ "_"
 where
  c' = if s == "" then c else s

--This makes up for the fact that there's no typedef in Java
typename t user = 
 if t == "Ident" 
  then "String" 
  else if t == "Char" 
  then "Character" 
  else if elem t user
  then "String"
  else t
