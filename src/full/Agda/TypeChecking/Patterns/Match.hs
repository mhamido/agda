{-# LANGUAGE NondecreasingIndentation #-}

-- | Pattern matcher used in the reducer for clauses that
--   have not been compiled to case trees yet.

module Agda.TypeChecking.Patterns.Match where

import Prelude hiding (null)

import Control.Monad
import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap

import Agda.Syntax.Common
import Agda.Syntax.Internal
import Agda.Syntax.Internal.Pattern

import Agda.TypeChecking.Reduce
import Agda.TypeChecking.Reduce.Monad
import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Monad hiding (constructorForm)
import Agda.TypeChecking.Monad.Builtin (getName', builtinHComp)
import Agda.TypeChecking.Pretty
import Agda.TypeChecking.Records

import Agda.Utils.Empty
import Agda.Utils.Functor (for, ($>), (<&>))
import Agda.Utils.Maybe
import Agda.Utils.Monad ( anyM, or2M)
import Agda.Utils.Null
import Agda.Utils.Singleton
import Agda.Utils.Size
import Agda.Utils.Tuple

import Agda.Utils.Impossible

-- | If matching is inconclusive (@DontKnow@) we want to know whether it is on a
--   lazy pattern and whether it is due to a particular meta variable.
data Match a = Yes Simplification (IntMap (Arg a))
             | No
             | DontKnow OnlyLazy (Blocked ())
  deriving Functor

instance Null (Match a) where
  empty = Yes empty empty
  null (Yes simpl as) = null simpl && null as
  null _              = False

matchedArgs :: Empty -> Int -> IntMap (Arg a) -> [Arg a]
matchedArgs err n vs = map (fromMaybe (absurd err)) $ matchedArgs' n vs

matchedArgs' :: Int -> IntMap (Arg a) -> [Maybe (Arg a)]
matchedArgs' n vs = map get [0 .. n - 1]
  where
    get k = IntMap.lookup k vs

-- | Builds a proper substitution from an IntMap produced by match(Co)patterns
buildSubstitution :: (DeBruijn a)
                  => Impossible -> Int -> IntMap (Arg a) -> Substitution' a
buildSubstitution err n vs = foldr cons idS $ matchedArgs' n vs
  where cons Nothing  = strengthenS' err 1
        cons (Just v) = consS (unArg v)


instance Semigroup (Match a) where
    -- @NotBlocked (StuckOn e)@ means blocked by a variable.
    -- In this case, no instantiation of meta-variables will make progress.
    DontKnow l b <> DontKnow l' b' = DontKnow (l <> l') (b <> b')
    DontKnow l m <> _              = DontKnow l m
    _            <> DontKnow l m   = DontKnow l m
    -- One could imagine DontKnow _ _ <> No = No, but would break the
    -- equivalence to case-trees (Issue 2964).
    No         <> _                = No
    _          <> No               = No
    Yes s us   <> Yes s' vs        = Yes (s <> s') (us <> vs)

instance Monoid (Match a) where
    mempty = empty
    mappend = (<>)

-- | Whether the inconclusive matches are only on lazy patterns.
data OnlyLazy = OnlyLazy | NonLazy

instance Semigroup OnlyLazy where
  NonLazy  <> _        = NonLazy
  _        <> NonLazy  = NonLazy
  OnlyLazy <> OnlyLazy = OnlyLazy

instance Monoid OnlyLazy where
  mempty = OnlyLazy
  mappend = (<>)

-- | Instead of 'zipWithM', we need to use this lazy version
--   of combining pattern matching computations.

-- Andreas, 2014-05-08, see Issue 1124:
--
-- Due to a bug in TypeChecking.Patterns.Match
-- a failed match of (C n b) against (C O unit)
-- turned into (C n unit).
-- This was because all patterns were matched in
-- parallel, and evaluations of successfull matches
-- (and a record constructor like unit can always
-- be successfully matched) were returned, leading
-- to a reassembly of (C n b) as (C n unit) which is
-- illtyped.

-- Now patterns are matched left to right and
-- upon failure, no further matching is performed.

foldMatch
  :: forall m p v . (IsProjP p, MonadMatch m)
  => (p -> v -> m (Match Term, v))
  -> [p] -> [v] -> m (Match Term, [v])
foldMatch match = loop where
  loop :: [p] -> [v] -> m (Match Term, [v])
  loop ps0 vs0 = do
    case (ps0, vs0) of
      ([], []) -> return (empty, [])
      (p : ps, v : vs) -> do
        (r, v') <- match p v
        case r of
          No | Just{} <- isProjP p -> return (No, v' : vs)
          No -> do
            -- Issue 2964: Even when the first pattern doesn't match we should
            -- continue to the next patterns (and potentially block on them)
            -- because the splitting order in the case tree may not be
            -- left-to-right.
            (r', _vs') <- loop ps vs
            -- Issue 2968: do not use vs' here, because it might
            -- contain ill-typed terms due to eta-expansion at wrong
            -- type.
            return (r <> r', v' : vs)
          DontKnow OnlyLazy _ -> do
            (r', _vs') <- loop ps vs
            return (r <> r', v' : vs)
          DontKnow NonLazy m -> return (DontKnow NonLazy m, v' : vs)
          Yes{} -> do
            (r', vs') <- loop ps vs
            return (r <> r', v' : vs')
      _ -> __IMPOSSIBLE__


-- TODO refactor matchPattern* to work with Elim instead.
mergeElim :: Elim -> Arg Term -> Elim
mergeElim Apply{} arg = Apply arg
mergeElim (IApply x y _) arg = IApply x y (unArg arg)
mergeElim Proj{} _ = __IMPOSSIBLE__

mergeElims :: [Elim] -> [Arg Term] -> [Elim]
mergeElims = zipWith mergeElim

type MonadMatch m = PureTCM m

-- | @matchCopatterns ps es@ matches spine @es@ against copattern spine @ps@.
--
--   Returns 'Yes' and a substitution for the pattern variables
--   (in form of IntMap Term) if matching was successful.
--
--   Returns 'No' if there was a constructor or projection mismatch.
--
--   Returns 'DontKnow' if an argument could not be evaluated to
--   constructor form because of a blocking meta variable.
--
--   In any case, also returns spine @es@ in reduced form
--   (with all the weak head reductions performed that were necessary
--   to come to a decision).
matchCopatterns :: MonadMatch m
                => [NamedArg DeBruijnPattern]
                -> [Elim]
                -> m (Match Term, [Elim])
matchCopatterns ps vs = do
  traceSDoc "tc.match" 50
    (vcat [ "matchCopatterns"
          , nest 2 $ "ps =" <+> fsep (punctuate comma $ map (prettyTCM . namedArg) ps)
          , nest 2 $ "vs =" <+> fsep (punctuate comma $ map prettyTCM vs)
          ]) $ do
  -- Buggy, see issue 1124:
  -- mapFst mconcat . unzip <$> zipWithM' (matchCopattern . namedArg) ps vs
  foldMatch (matchCopattern . namedArg) ps vs

-- | Match a single copattern.
matchCopattern :: MonadMatch m
               => DeBruijnPattern
               -> Elim
               -> m (Match Term, Elim)
matchCopattern pat@ProjP{} elim@(Proj _ q) = do
  p <- normaliseProjP pat <&> \case
         ProjP _ p -> p
         _         -> __IMPOSSIBLE__
  q       <- getOriginalProjection q
  return $ if p == q then (Yes YesSimplification empty, elim)
                     else (No,                          elim)
-- The following two cases are not impossible, see #2964
matchCopattern ProjP{} elim@Apply{}   = return (No , elim)
matchCopattern _       elim@Proj{}    = return (No , elim)
matchCopattern p       (Apply v) = mapSnd Apply <$> matchPattern p v
matchCopattern p       e@(IApply x y r) = mapSnd (mergeElim e) <$> matchPattern p (defaultArg r)

{-# SPECIALIZE matchPatterns :: [NamedArg DeBruijnPattern] -> [Arg Term] -> TCM (Match Term, [Arg Term]) #-}
matchPatterns :: MonadMatch m
              => [NamedArg DeBruijnPattern]
              -> [Arg Term]
              -> m (Match Term, [Arg Term])
matchPatterns ps vs = do
  reportSDoc "tc.match" 20 $
     vcat [ "matchPatterns"
          , nest 2 $ "ps =" <+> prettyTCMPatternList ps
          , nest 2 $ "vs =" <+> fsep (punctuate comma $ map prettyTCM vs)
          ]

  traceSDoc "tc.match" 50
    (vcat [ "matchPatterns"
          , nest 2 $ "ps =" <+> fsep (punctuate comma $ map (text . show) ps)
          , nest 2 $ "vs =" <+> fsep (punctuate comma $ map prettyTCM vs)
          ]) $ do
  -- Buggy, see issue 1124:
  -- (ms,vs) <- unzip <$> zipWithM' (matchPattern . namedArg) ps vs
  -- return (mconcat ms, vs)
  foldMatch (matchPattern . namedArg) ps vs

-- | Match a single pattern.
matchPattern :: MonadMatch m
             => DeBruijnPattern
             -> Arg Term
             -> m (Match Term, Arg Term)
matchPattern p u = case (p, u) of
  (ProjP{}, _            ) -> __IMPOSSIBLE__
  (IApplyP _ _ _ x , arg ) -> return (Yes NoSimplification entry, arg)
    where entry = singleton (dbPatVarIndex x, arg)
  (VarP _ x , arg          ) -> return (Yes NoSimplification entry, arg)
    where entry = singleton (dbPatVarIndex x, arg)
  (DotP _ _ , arg@(Arg _ v)) -> return (Yes NoSimplification empty, arg)
  (LitP _ l , arg@(Arg _ v)) -> do
    w <- reduceB v
    let arg' = arg $> ignoreBlocking w
    case w of
      NotBlocked _ (Lit l')
          | l == l'            -> return (Yes YesSimplification empty , arg')
          | otherwise          -> return (No                          , arg')
      Blocked b _              -> return (DontKnow NonLazy $ Blocked b ()     , arg')
      NotBlocked r t           -> return (DontKnow NonLazy $ NotBlocked r' () , arg')
        where r' = stuckOn (Apply arg') r

  -- Case constructor pattern.
  (ConP c cpi ps, Arg info v) -> do
    let lazy = if conPLazy cpi then OnlyLazy else NonLazy
    if not (conPRecord cpi) then fallback c lazy ps (Arg info v) else do
    isEtaRecordConstructor (conName c) >>= \case
      Nothing -> fallback c lazy ps (Arg info v)
      -- Case: Eta record constructor.
      -- This case is necessary if we want to use the clauses before
      -- record pattern translation (e.g., in type-checking definitions by copatterns).
      Just (_r, def) -> do
        reportSDoc "tc.match" 50 $ vcat
          [ "matchPattern: eta record"
          , nest 2 $ "c  = " <+> prettyTCM c
          , nest 2 $ "ps = " <+> prettyTCMPatternList ps
          , nest 2 $ "v  = " <+> prettyTCM v
          ]
        -- Issue #7266: in case we are brazenly matching potentially ill-typed arguments,
        -- `v` might be an application of a *different* constructor.
        -- In that case we certainly have no match.
        case v of
          Con c' _ _ | c /= c' -> return (No, u)
          _ -> do
            let fs = map argFromDom $ _recFields def
            unless (size fs == size ps) __IMPOSSIBLE__
            mapSnd (Arg info . Con c (fromConPatternInfo cpi) . map Apply) <$> do
              matchPatterns ps $ for fs $ \ (Arg ai f) -> Arg ai $ v `applyE` [Proj ProjSystem f]
  (DefP o q ps, v) -> do
    let f (Def q' vs) | q == q' = Just (Def q, vs)
        f _                     = Nothing
    fallback' f NonLazy ps v
 where
    -- Default: not an eta record constructor.
  fallback :: MonadMatch m
           => ConHead -> OnlyLazy -> [NamedArg DeBruijnPattern] -> Arg Term -> m (Match Term, Arg Term)
  fallback c lazy ps v = do
    let f (Con c' ci' vs) | c == c' = Just (Con c' ci',vs)
        f _                         = Nothing
    fallback' f lazy ps v

  -- Regardless of blocking, constructors and a properly applied @hcomp@
  -- can be matched on.
  isMatchable' :: HasBuiltins m => m (Blocked Term -> Maybe Term)
  isMatchable' = do
    mhcomp <- getName' builtinHComp
    return $ \ r ->
      case ignoreBlocking r of
        t@Con{} -> Just t
        t@(Def q [l,a,phi,u,u0]) | Just q == mhcomp
                -> Just t
        -- TODO this covers the transpIx functions, but it's a hack.
        t@(Def q _) | NotBlocked{blockingStatus = MissingClauses _} <- r -> Just t
        _       -> Nothing

  -- DefP hcomp and ConP matching.
  fallback' :: MonadMatch m
            => (Term -> Maybe (Elims -> Term , Elims))
            -> OnlyLazy
            -> [NamedArg DeBruijnPattern]
            -> Arg Term
            -> m (Match Term, Arg Term)
  fallback' mtc lazy ps (Arg info v) = do
        isMatchable <- isMatchable'

        w <- reduceB v
        -- Unfold delayed (corecursive) definitions one step. This is
        -- only necessary if c is a coinductive constructor, but
        -- it does not hurt to do it all the time.
{-
        w <- case w of
               NotBlocked r (Def f es) ->   -- Andreas, 2014-06-12 TODO: r == ReallyNotBlocked sufficient?
                 unfoldDefinitionE True reduceB' (Def f []) f es
                   -- reduceB is used here because some constructors
                   -- are actually definitions which need to be
                   -- unfolded (due to open public).
               _ -> return w
-}
        -- Jesper, 23-06-2016: Note that unfoldCorecursion may destroy
        -- constructor forms, so we only call constructorForm after.
        w <- traverse constructorForm =<< case w of
               NotBlocked r u -> liftReduce $ unfoldCorecursion u  -- Andreas, 2014-06-12 TODO: r == ReallyNotBlocked sufficient?
               _ -> return w
        let v = ignoreBlocking w
            arg = Arg info v  -- the reduced argument

        case w of
          b | Just t <- isMatchable b ->
            case mtc t of
              Just (bld, vs) -> do
                (m, vs1) <- matchPatterns ps (fromMaybe __IMPOSSIBLE__ $ allApplyElims vs)
                return (yesSimplification m, Arg info $ bld (mergeElims vs vs1))
              Nothing
                                    -> return (No                          , arg)
          Blocked b _               -> return (DontKnow lazy $ Blocked b ()     , arg)
          NotBlocked r _            -> return (DontKnow lazy $ NotBlocked r' () , arg)
            where r' = stuckOn (Apply arg) r

yesSimplification :: Match a -> Match a
yesSimplification = \case
  Yes _ vs -> Yes YesSimplification vs
  m -> m

-- Matching patterns against patterns -------------------------------------

-- | Match a single pattern.
matchPatternP :: MonadMatch m
              => DeBruijnPattern
              -> Arg DeBruijnPattern
              -> m (Match DeBruijnPattern)
matchPatternP p (Arg info (DotP _ v)) = do
  (m, arg) <- matchPattern p (Arg info v)
  return $ fmap (DotP defaultPatternInfo) m
matchPatternP p arg@(Arg info q) = do
  let varMatch x = return $ Yes NoSimplification $ singleton (dbPatVarIndex x, arg)
      termMatch  = do
        (m, arg) <- matchPattern p (fmap patternToTerm arg)
        return $ fmap (DotP defaultPatternInfo) m
  case p of
    ProjP{}         -> __IMPOSSIBLE__
    IApplyP _ _ _ x -> varMatch x
    VarP _ x        -> varMatch x
    DotP _ _        -> return $ Yes NoSimplification empty
    LitP{}          -> termMatch -- Literal patterns bind no variables so we can fall back to the Term version.
    DefP{}          -> termMatch

    ConP c cpi ps ->
      case q of
        ConP c' _ qs | c == c'   -> matchPatternsP ps ((map . fmap) namedThing qs)
                     | otherwise -> return No
        LitP{} -> fmap toLitP <$> termMatch
          where toLitP (DotP _ (Lit l)) = litP l   -- All bindings should be to literals
                toLitP _                = __IMPOSSIBLE__
        _      -> termMatch

matchPatternsP :: MonadMatch m
               => [NamedArg DeBruijnPattern]
               -> [Arg DeBruijnPattern]
               -> m (Match DeBruijnPattern)
matchPatternsP ps qs = do
  mconcat <$> zipWithM matchPatternP (map namedArg ps) qs


-- | Does the pattern perform a match that could fail?
properlyMatching :: HasConstInfo m => Pattern' a -> m Bool
properlyMatching = properlyMatching' True True

properlyMatching' :: HasConstInfo m
  => Bool       -- ^ Should absurd patterns count as proper match?
  -> Bool       -- ^ Should projection patterns count as proper match?
  -> Pattern' a -- ^ The pattern.
  -> m Bool
properlyMatching' absP projP = \case
  p | absP && patternOrigin p == Just PatOAbsurd -> return True
  ConP con ci ps    -- eta record constructors do not count as proper matches themselves
    | conPRecord ci -> (isNothing <$> isEtaRecordConstructor (conName con)) `or2M` anyM (properlyMatching . namedArg) ps
    | otherwise     -> return True
  LitP{}    -> return True
  DefP{}    -> return True
  ProjP{}   -> return projP
  VarP{}    -> return False
  DotP{}    -> return False
  IApplyP{} -> return False
