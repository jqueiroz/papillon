module Text.Papillon.SyntaxTree where

import Language.Haskell.TH
import Data.Char
import Control.Applicative
import Data.List

type Leaf = (ReadFrom, ExR)
data ReadFrom
	= FromVariable String
	| FromSelection Selection
	| FromToken
	| FromList ReadFrom
	| FromList1 ReadFrom
	| FromOptional ReadFrom

showLeaf :: Leaf -> Q String
showLeaf (rf, ex) = do
	rff <- showReadFrom rf
	exx <- ex
	return $ rff ++ "[" ++ show (ppr exx) ++ "]"

showReadFrom :: ReadFrom -> Q String
showReadFrom FromToken = return ""
showReadFrom (FromVariable v) = return v
showReadFrom (FromList rf) = (++ "*") <$> showReadFrom rf
showReadFrom (FromList1 rf) = (++ "+") <$> showReadFrom rf
showReadFrom (FromOptional rf) = (++ "?") <$> showReadFrom rf
showReadFrom (FromSelection sel) = ('(' :) <$> (++ ")") <$> showSelection sel

data NameLeaf = NameLeaf PatQ ReadFrom ExR

showNameLeaf :: NameLeaf -> Q String
showNameLeaf (NameLeaf pat rf p) = do
	patt <- pat
	rff <- showReadFrom rf
	pp <- p
	return $ show (ppr patt) ++ ":" ++ rff ++ "[" ++ show (ppr pp) ++ "]"

data NameLeaf_
	= Here NameLeaf
	| After NameLeaf
	| NotAfter NameLeaf

showNameLeaf_ :: NameLeaf_ -> Q String
showNameLeaf_ (Here nl) = showNameLeaf nl
showNameLeaf_ (After nl) = ('&' :) <$> showNameLeaf nl
showNameLeaf_ (NotAfter nl) = ('!' :) <$> showNameLeaf nl

notAfter, here :: NameLeaf -> NameLeaf_
notAfter = NotAfter
here = Here
type Expression = [NameLeaf_]

showExpression :: Expression -> Q String
showExpression ex = unwords <$> mapM showNameLeaf_ ex

type ExpressionHs = (Expression, ExR)

showExpressionHs :: ExpressionHs -> Q String
showExpressionHs (ex, hs) = do
	expp <- showExpression ex
	hss <- hs
	return $ expp ++ " { " ++ show (ppr hss) ++ " }"

type Selection = [ExpressionHs]

showSelection :: Selection -> Q String
showSelection ehss = (intercalate " / ") <$> mapM showExpressionHs ehss

type Definition = (String, TypeQ, Selection)
type Peg = [Definition]
type TTPeg = (TypeQ, TypeQ, Peg)

type Ex = (ExpQ -> ExpQ) -> ExpQ
type ExR = ExpQ
type ExRL = [ExpQ]

type Typ = (TypeQ -> TypeQ) -> TypeQ
type TypeQL = [TypeQ]

tupT :: [TypeQ] -> TypeQ
tupT ts = foldl appT (tupleT $ length ts) ts

getTyp :: Typ -> TypeQ
getTyp t = t id

toTyp :: TypeQ -> Typ
toTyp tp = \f -> f tp

ctLeaf :: Leaf
ctLeaf = (FromToken, conE $ mkName "True")

ruleLeaf :: String -> ExpQ -> Leaf
boolLeaf :: ExpQ -> Leaf
ruleLeaf r t = (FromVariable r, t)
boolLeaf p = (FromToken, p)

true :: ExpQ
true = conE $ mkName "True"

just :: a -> Maybe a
just = Just
nothing :: Maybe a
nothing = Nothing

cons :: a -> [a] -> [a]
cons = (:)

type PatQs = [PatQ]

mkNameLeaf :: PatQ -> Leaf -> NameLeaf
mkNameLeaf n (f, p) = NameLeaf n f p

strToPatQ :: String -> PatQ
strToPatQ = varP . mkName

conToPatQ :: String -> [PatQ] -> PatQ
conToPatQ t ps = conP (mkName t) ps

mkExpressionHs :: a -> ExR -> (a, ExR)
mkExpressionHs x y = (x, y)

mkDef :: a -> TypeQ -> c -> (a, TypeQ, c)
mkDef x y z = (x, y, z)

isOpTailChar :: Char -> Bool
isOpTailChar = (`elem` ":+*/-!|&.^=<>$")

colon :: Char
colon = ':'

isOpHeadChar :: Char -> Bool
isOpHeadChar = (`elem` "+*/-!|&.^=<>$")

toExp :: String -> Ex
toExp v = \f -> f $ varE (mkName v)

toEx :: ExR -> Ex
toEx v = \f -> f v

apply :: String -> Ex -> Ex
apply f x = \g -> x (toExp f g `appE`)

applyExR :: ExR -> Ex -> Ex
applyExR f x = \g -> x (toEx f g `appE`)

applyTyp :: Typ -> Typ -> Typ
applyTyp f t = \g -> t (f g `appT`)

getEx :: Ex -> ExR
getEx ex = ex id -- (varE $ mkName "id")

toExGetEx :: Ex -> Ex
toExGetEx = toEx . getEx

emp :: [a]
emp = []

type PegFile = (String, String, TTPeg, String)
mkPegFile :: Maybe String -> Maybe String -> String -> String -> TTPeg -> String
	-> PegFile
mkPegFile (Just p) (Just md) x y z w =
	("{-#" ++ p ++ addPragmas ++ "module " ++ md ++ " where\n" ++
	addModules,
	x ++ "\n" ++ y, z, w)
mkPegFile Nothing (Just md) x y z w =
	(x ++ "\n" ++ "module " ++ md ++ " where\n" ++
	addModules,
	x ++ "\n" ++ y, z, w)
mkPegFile (Just p) Nothing x y z w = (
	"{-#" ++ p ++ addPragmas ++
	addModules,
	x ++ "\n" ++ y
	, z, w)
mkPegFile Nothing Nothing x y z w = (addModules, x ++ "\n" ++ y, z, w)

addPragmas, addModules :: String
addPragmas =
	", FlexibleContexts, PackageImports, TypeFamilies, RankNTypes, " ++
	"FlexibleInstances #-}\n"
addModules =
	"import \"monads-tf\" Control.Monad.State\n" ++
	"import \"monads-tf\" Control.Monad.Error\n" ++
	"import Control.Monad.Trans.Error (Error (..))\n" ++
	"import Language.Haskell.TH\n"
--	"import Control.Applicative\n"

charP :: Char -> PatQ
charP = litP . charL
stringP :: String -> PatQ
stringP = litP . stringL

isAlphaNumOt, elemNTs :: Char -> Bool
isAlphaNumOt c = isAlphaNum c || c `elem` "{-#.\":}|[]!;=/ *(),+<>?`&"
elemNTs = (`elem` "nt\\'")

isComma, isKome, isOpen, isClose, isGt, isQuestion, isBQ, isAmp :: Char -> Bool
isComma = (== ',')
isKome = (== '*')
isOpen = (== '(')
isClose = (== ')')
isGt = (== '>')
isQuestion = (== '?')
isBQ = (== '`')
isAmp = (== '&')

getNTs :: Char -> Char
getNTs 'n' = '\n'
getNTs 't' = '\t'
getNTs '\\' = '\\'
getNTs '\'' = '\''
getNTs o = o
isLowerU :: Char -> Bool
isLowerU c = isLower c || c == '_'

tString :: String
tString = "String"
mkTTPeg :: String -> Peg -> TTPeg
mkTTPeg s p =
	(conT $ mkName s, conT (mkName "Token") `appT` conT (mkName s), p)
