{-# LANGUAGE TupleSections #-}

module Text.Papillon.SyntaxTree (
	Peg,
	Definition,
	NP(..), Selection,
	Expression(..),
	HA(..), NameLeaf(..),
	ReadFrom(..),
	fromTokenChars,

	showSelection,
	showNameLeaf,
	getDefinitionType,
	getSelectionType,
	nameFromSelection,
	nameFromRF,

	PegFile,
	mkPegFile,
	PPragma(..),
	ModuleName,
	ExportList,
	Code
) where

import Language.Haskell.TH
import Control.Applicative
import Control.Arrow
import Data.List
import Data.Maybe

type Peg = [Definition]
type Definition = (String, Maybe TypeQ, Selection)
data NP = Normal | Plain deriving Show
type Selection = (NP, [Expression])
data Expression
	= Expression {
		expressionHsExpression :: [(HA, NameLeaf)],
		expressionHsExR :: ExpQ
	 }
	| ExpressionSugar ExpQ
	| PlainExpression [(HA, ReadFrom)]
data HA = Here | After | NotAfter String deriving (Show, Eq)
data NameLeaf = NameLeaf (PatQ, String) ReadFrom (Maybe (ExpQ, String))
data ReadFrom
	= FromVariable (Maybe String)
	| FromSelection Selection
	| FromList ReadFrom
	| FromList1 ReadFrom
	| FromOptional ReadFrom
fromTokenChars :: String -> ReadFrom
fromTokenChars cs =
	FromSelection $ (Normal ,) $ (: []) $ ExpressionSugar $
		infixE Nothing (varE $ mkName "elem") $ Just $ litE $ stringL cs

showSelection :: Selection -> Q String
showSelection (Normal, ehss) = intercalate " / " <$> mapM showExpression ehss
showSelection (Plain, ehss) = intercalate " / " <$> mapM showExpression ehss

showExpression :: Expression -> Q String
showExpression (Expression ex hs) =
	(\e h -> unwords e ++ " { " ++ show (ppr h) ++ " }")
		<$> mapM (uncurry (<$>) . (((++) . showHA) *** showNameLeaf)) ex
		<*> hs
showExpression (ExpressionSugar hs) = ('<' :) . (++ ">") . show . ppr <$> hs
showExpression (PlainExpression rfs) =
	unwords <$> mapM (\(ha, rf) -> (showHA ha ++) <$> showReadFrom rf) rfs

showHA :: HA -> String
showHA Here = ""
showHA After = "&"
showHA (NotAfter _) = "!"

showNameLeaf :: NameLeaf -> Q String
showNameLeaf (NameLeaf (pat, _) rf (Just (p, _))) = do
	patt <- pat
	rff <- showReadFrom rf
	pp <- p
	return $ show (ppr patt) ++ ":" ++ rff ++ "[" ++ show (ppr pp) ++ "]"
showNameLeaf (NameLeaf (pat, _) rf Nothing) = do
	patt <- pat
	rff <- showReadFrom rf
	return $ show (ppr patt) ++ ":" ++ rff

showReadFrom :: ReadFrom -> Q String
showReadFrom (FromVariable (Just v)) = return v
showReadFrom (FromVariable _) = return ""
showReadFrom (FromList rf) = (++ "*") <$> showReadFrom rf
showReadFrom (FromList1 rf) = (++ "+") <$> showReadFrom rf
showReadFrom (FromOptional rf) = (++ "?") <$> showReadFrom rf
showReadFrom (FromSelection sel) = ('(' :) <$> (++ ")") <$> showSelection sel

getDefinitionType :: Peg -> TypeQ -> Definition -> TypeQ
getDefinitionType _ _ (_, (Just typ), _) = typ
getDefinitionType peg tknt (_, _, sel) = getSelectionType peg tknt sel

getSelectionType :: Peg -> TypeQ -> Selection -> TypeQ
getSelectionType peg tknt (Plain, ex) =
	foldr (\x y -> (eitherT `appT` x) `appT` y) (last types) (init types)
	where
	eitherT = conT $ mkName "Either"
	types = map (getExpressionType peg tknt) ex
getSelectionType _ tknt (Normal, [ExpressionSugar _]) = tknt
getSelectionType _ _ _ = error "getSelectionType: can't get type"

getExpressionType :: Peg -> TypeQ -> Expression -> TypeQ
getExpressionType peg tknt (PlainExpression rfs) =
	foldl appT (tupleT $ length $ filter ((== Here) . fst) rfs) $ catMaybes $
		map (getHAReadFromType peg tknt) rfs
getExpressionType _ _ _ = error "getExpressionType: can't get type"

getHAReadFromType :: Peg -> TypeQ -> (HA, ReadFrom) -> Maybe TypeQ
getHAReadFromType peg tknt (Here, rf) = Just $ getReadFromType peg tknt rf
getHAReadFromType _ _ _ = Nothing

getReadFromType :: Peg -> TypeQ -> ReadFrom -> TypeQ
getReadFromType peg tknt (FromVariable (Just var)) =
	getDefinitionType peg tknt $ searchDefinition peg var
getReadFromType peg tknt (FromSelection sel) = getSelectionType peg tknt sel
getReadFromType _ tknt (FromVariable _) = tknt
getReadFromType peg tknt (FromList rf) = listT `appT` getReadFromType peg tknt rf
getReadFromType peg tknt (FromList1 rf) = listT `appT` getReadFromType peg tknt rf
getReadFromType peg tknt (FromOptional rf) =
	conT (mkName "Maybe") `appT` getReadFromType peg tknt rf

searchDefinition :: Peg -> String -> Definition
searchDefinition peg var = case filter ((== var) . \(n, _, _) -> n) peg of
	[d] -> d
	_ -> error "searchDefinition: bad"

nameFromSelection :: Selection -> [String]
nameFromSelection (Normal, exs) = concatMap nameFromExpression exs
nameFromSelection (Plain, exs) = concatMap nameFromExpression exs

nameFromExpression :: Expression -> [String]
nameFromExpression (Expression ex _) = nameFromNameLeaf $ snd $ head ex
nameFromExpression (ExpressionSugar _) = []
nameFromExpression (PlainExpression rfs) = concatMap (nameFromRF . snd) rfs

nameFromNameLeaf :: NameLeaf -> [String]
nameFromNameLeaf (NameLeaf _ rf _) = nameFromRF rf

nameFromRF :: ReadFrom -> [String]
nameFromRF (FromVariable (Just s)) = [s]
nameFromRF (FromVariable _) = ["char"]
nameFromRF (FromList rf) = nameFromRF rf
nameFromRF (FromList1 rf) = nameFromRF rf
nameFromRF (FromOptional rf) = nameFromRF rf
nameFromRF (FromSelection sel) = nameFromSelection sel

type PegFile =
	([PPragma], ModuleName, Maybe ExportList, Code, (TypeQ, Peg), Code)
data PPragma = LanguagePragma [String] | OtherPragma String deriving Show
type ModuleName = [String]
type ExportList = String
type Code = String

mkPegFile :: [PPragma] -> Maybe ([String], Maybe String) -> String -> String ->
	(TypeQ, Peg) -> String -> PegFile
mkPegFile ps (Just md) x y z w = (ps, fst md, snd md, x ++ "\n" ++ y, z, w)
mkPegFile ps Nothing x y z w = (ps, [], Nothing, x ++ "\n" ++ y, z, w)
