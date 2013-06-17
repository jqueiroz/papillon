{-# LANGUAGE PackageImports #-}

module ParsePeg3 (
	parse,
	dvDefinition,
	runQ,
	ppr
) where

import Control.Applicative
import Control.Monad
import "monads-tf" Control.Monad.State
import Data.Char
import Language.Haskell.TH

type PMonad = StateT Derivs Maybe

type Result v = Maybe (v, Derivs)

type Peg = [Definition]

type Definition = (Name, Name, Selection)

type Selection = [Expression]

type Expression = ([NameLeaf], ExpQ)

type NameLeaf = (Name, Leaf)

type Leaf = Either String ExpQ

data Derivs = Derivs {
	dvPeg :: Result Peg,
	dvDefinition :: Result Definition,
	dvSelection :: Result Selection,
	dvExpression :: Result Expression,
	dvNameLeafs :: Result [NameLeaf],
	dvNameLeaf :: Result NameLeaf,
	dvLeaf :: Result Leaf,
	dvHsExpression :: Result ExpQ,
	dvType :: Result String,
	dvVariable :: Result String,
	dvTail :: Result String,
	dvChars :: Result Char
 }

dvDefinitionM :: PMonad Definition
dvDefinitionM = StateT dvDefinition

dvExpressionM :: PMonad Expression
dvExpressionM = StateT dvExpression

dvNameLeafsM :: PMonad [NameLeaf]
dvNameLeafsM = StateT dvNameLeafs

dvNameLeafM :: PMonad NameLeaf
dvNameLeafM = StateT dvNameLeaf

dvLeafM :: PMonad Leaf
dvLeafM = StateT dvLeaf

dvHsExpressionM :: PMonad ExpQ
dvHsExpressionM = StateT dvHsExpression

dvTypeM :: PMonad String
dvTypeM = StateT dvType

dvVariableM :: PMonad String
dvVariableM = StateT dvVariable

dvTailM :: PMonad String
dvTailM = StateT dvTail

dvCharsM :: PMonad Char
dvCharsM = StateT dvChars

parse :: String -> Derivs
parse s = d where
	d = Derivs
		undefined definition undefined expression nameLeafs nameLeaf leaf
		hsExpression typ variable tail chr
	definition = runStateT pDefinition d
	expression = runStateT pExpression d
	nameLeafs = runStateT pNameLeafs d
	nameLeaf = runStateT pNameLeaf d
	leaf = runStateT pLeaf d
	hsExpression = runStateT pHsExpression d
	typ = runStateT pType d
	variable = runStateT pVariable d
	tail = runStateT pTail d
	chr = flip runStateT d $ do
		c : s' <- return s
		put $ parse s'
		return c

pDefinition :: PMonad Definition
pDefinition = (\v _ _ _ _ t _ _ _ _ expr -> (mkName v, mkName t, [expr]))
	<$> dvVariableM
	<*> do { ' ' <- dvCharsM; return () }
	<*> do { ':' <- dvCharsM; return () }
	<*> do { ':' <- dvCharsM; return () }
	<*> do { ' ' <- dvCharsM; return () }
	<*> dvTypeM
	<*> do { '\n' <- dvCharsM; return () }
	<*> do { '\t' <- dvCharsM; return () }
	<*> do { '=' <- dvCharsM; return () }
	<*> do { ' ' <- dvCharsM; return () }
	<*> dvExpressionM

pExpression :: PMonad Expression
pExpression = (\nls _ _ _ hse _ _ -> (nls, hse))
	<$> dvNameLeafsM
	<*> do { '\t' <- dvCharsM; return () }
	<*> do { '{' <- dvCharsM; return () }
	<*> do { ' ' <- dvCharsM; return () }
	<*> dvHsExpressionM
	<*> do { ' ' <- dvCharsM; return () }
	<*> do { '}' <- dvCharsM; return () }

pNameLeafs :: PMonad [NameLeaf]
pNameLeafs = msum [((\nl _ nls -> nl : nls)
	<$> pNameLeaf
	<*> do { ' ' <- dvCharsM; return () }
	<*> pNameLeafs),
	(:[]) <$> pNameLeaf,
	return []]

pNameLeaf :: PMonad NameLeaf
pNameLeaf = (\v _ l -> (mkName v, l))
	<$> dvVariableM
	<*> do { ':' <- dvCharsM; return () }
	<*> dvLeafM

pLeaf :: PMonad Leaf
pLeaf = (Left <$> dvVariableM) `mplus` (Right <$> (do
	'[' <- dvCharsM
	v <- dvHsExpressionM
	']' <- dvCharsM
	return v))

pHsExpression :: PMonad ExpQ
pHsExpression = msum [
	(\f _ x -> f `appE` x)
		<$> (varE <$> mkName <$> dvVariableM)
		<*> do { ' ' <- dvCharsM; return () }
		<*> dvHsExpressionM,
	varE <$> mkName <$> dvVariableM
 ]

pType :: PMonad String
pType = do
	c <- dvCharsM
	if isUpper c
	then (c :) <$> dvTailM
	else fail "not match"

pVariable :: PMonad String
pVariable = do
	c <- dvCharsM
	if isLower c then (c :) <$> dvTailM else fail "not match"

pTail :: PMonad String
pTail = msum [do
	c <- dvCharsM
	if isAlpha c then (c :) <$> dvTailM else fail "not match",
	return ""]
