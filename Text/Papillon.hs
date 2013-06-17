{-# LANGUAGE TemplateHaskell, PackageImports #-}

module Text.Papillon (
	papillon,
	StateT(..)
) where

import Language.Haskell.TH.Quote
import Language.Haskell.TH
import "monads-tf" Control.Monad.State

papillon :: QuasiQuoter
papillon = QuasiQuoter {
	quoteExp = undefined,
	quotePat = undefined,
	quoteType = undefined,
	quoteDec = declaration
 }

declaration :: String -> DecsQ
declaration src = do
{-
	parseT <- sigD (mkName "parse") $
		arrowT `appT` conT (mkName "String") `appT`
			(conT (mkName "Maybe") `appT`
				(tupleT 2
					`appT` conT (mkName "Int")
					`appT` conT (mkName "Int")))
	parse <- funD (mkName "parse") [c] -- valD (varP $ mkName "parse") (normalB $ litE $ integerL 8) []
	dvSome <- valD (varP $ mkName "dvSome") (normalB $ varE $ mkName "id") []
-}
	debug <- flip (valD $ varP $ mkName "debug") [] $ normalB $
		appE (varE $ mkName "putStrLn") (litE $ stringL "debug")
	r <- result
	pm <- pmonad
	d <- derivs
	pt <- parseT
	p <- funD (mkName "parse") [parse]
	dvsm <- dvSomeM
	dvcm <- dvCharsM
	ps <- pSome
--	return [parseT, parse, dvSome, debug, d, ps]
	return [debug, r, pm, d, pt, p, dvsm, dvcm, ps]
	where
	c = clause [wildP] (normalB $ conE $ mkName "Nothing") []

derivs :: DecQ
derivs = flip (dataD (cxt []) (mkName "Derivs") []) [] $ [
	recC (mkName "Derivs") [
		varStrictType (mkName "dvSome") $ strictType notStrict $
			conT (mkName "Result") `appT` conT ''Char,
		varStrictType (mkName "dvChars") $ strictType notStrict $
			conT (mkName "Result") `appT` conT ''Char
	 ]
 ]

result :: DecQ
result = tySynD (mkName "Result") [PlainTV $ mkName "v"] $ conT ''Maybe `appT`
	(tupleT 2 `appT` varT (mkName "v") `appT` conT (mkName "Derivs"))
pmonad :: DecQ
pmonad = tySynD (mkName "PMonad") [] $ conT ''StateT `appT`
	conT (mkName "Derivs") `appT` conT ''Maybe

parseT :: DecQ
parseT = sigD (mkName "parse") $
	arrowT `appT` conT ''String `appT` conT (mkName "Derivs")
parse :: ClauseQ
parse = clause [varP $ mkName "s"] (normalB $ varE $ mkName "d") [
	flip (valD $ varP $ mkName "d") [] $ normalB $ (conE $ mkName "Derivs")
		`appE` (varE $ mkName "some")
		`appE` (varE $ mkName "chr"),
	flip (valD $ varP $ mkName "some") [] $ normalB $
		(varE $ mkName "runStateT") `appE` (varE $ mkName "pSome") `appE`
			(varE $ mkName "d"),
	flip (valD $ varP $ mkName "chr") [] $ normalB $
		(varE $ mkName "flip") `appE` (varE $ mkName "runStateT") `appE`
			(varE $ mkName "d") `appE` (doE [
				bindS	(infixP (varP $ mkName "c") (mkName ":")
						(varP $ mkName "s'")) $
					(varE 'return) `appE`
						(varE $ mkName "s"),
				noBindS $ (varE 'put) `appE`
					(varE (mkName "parse") `appE`
						varE (mkName "s'")),
				noBindS $ (varE 'return) `appE` varE (mkName "c")
			 ])
 ]

dvSomeM, dvCharsM :: DecQ
dvSomeM = flip (valD $ varP $ mkName "dvSomeM") [] $ normalB $
	conE 'StateT `appE` varE (mkName "dvSome")
dvCharsM = flip (valD $ varP $ mkName "dvCharsM") [] $ normalB $
	conE 'StateT `appE` varE (mkName "dvChars")

pSome :: DecQ
pSome = flip (valD $ varP $ mkName "pSome") [] $ normalB $ doE [
	bindS (varP $ mkName "d") $ varE $ mkName "dvCharsM",
	noBindS $ condE (varE (mkName "isDigit") `appE` varE (mkName "d"))
		(varE (mkName "return") `appE` varE (mkName "d"))
		(varE (mkName "fail") `appE` litE (stringL "not match"))
 ]
