{-# LANGUAGE DeriveDataTypeable #-}

-- | Data types similar to @Data.Either@ that are explicit about failure and success.
module Data.Validation
(
  AccValidation
, Validation
, ValidationT(..)
, Validate(..)
) where

import Control.Applicative
import Data.Foldable
import Data.Traversable
import Data.Bifunctor
import Data.Bifoldable
import Data.Bitraversable
import Data.Functor.Bind
import Data.Functor.Alt
import Data.Semigroup
import Data.Typeable
import Data.Data
import Prelude hiding (foldr)

-- | A value of the type @err@ or @a@, however, the @Applicative@ instance
-- accumulates values. This is witnessed by the @Semigroup@ context on the instance.
-- /Note that there is no @Monad@ such that @ap = (<*>)./
--
-- * @success (+1) <*> success 7 == AccSuccess 8@
--
-- * @failure ["f1"] <*> success 7 == AccFailure ["f1"]@
--
-- * @success (+1) <*> failure ["f2"] == AccFailure ["f2"]@
--
-- * @failure ["f1"] <*> failure ["f2"] == AccFailure ["f1","f2"]@
data AccValidation err a =
  AccFailure err
  | AccSuccess a
  deriving (Eq, Ord, Show, Data, Typeable)

instance Functor (AccValidation err) where
  fmap _ (AccFailure e) =
    AccFailure e
  fmap f (AccSuccess a) =
    AccSuccess (f a)

instance Semigroup err => Apply (AccValidation err) where
  AccFailure e1 <.> AccFailure e2 =
    AccFailure (e1 <> e2)
  AccFailure e1 <.> AccSuccess _  =
    AccFailure e1
  AccSuccess _  <.> AccFailure e2 =
    AccFailure e2
  AccSuccess f  <.> AccSuccess a  =
    AccSuccess (f a)

instance Semigroup err => Applicative (AccValidation err) where
  pure =
    AccSuccess
  (<*>) =
    (<.>)

instance Semigroup err => Alt (AccValidation err) where
  AccFailure _ <!> x =
    x
  AccSuccess a <!> _ =
    AccSuccess a

instance (Semigroup err, Monoid err) => Alternative (AccValidation err) where
  AccFailure _ <|> x =
    x
  AccSuccess a <|> _ =
    AccSuccess a
  empty =
    AccFailure mempty

instance Foldable (AccValidation err) where
  foldr f x (AccSuccess a) =
    f a x
  foldr _ x (AccFailure _) =
    x

instance Traversable (AccValidation err) where
  traverse f (AccSuccess a) =
    AccSuccess <$> f a
  traverse _ (AccFailure e) =
    pure (AccFailure e)

instance Bifunctor AccValidation where
  bimap f _ (AccFailure e) =
    AccFailure (f e)
  bimap _ g (AccSuccess a) =
    AccSuccess (g a)

instance Bifoldable AccValidation where
  bifoldr _ g x (AccSuccess a) =
    g a x
  bifoldr f _ x (AccFailure e) =
    f e x

instance Bitraversable AccValidation where
  bitraverse _ g (AccSuccess a) =
    AccSuccess <$> g a
  bitraverse f _ (AccFailure e) =
    AccFailure <$> f e

instance Semigroup e => Semigroup (AccValidation e a) where
  AccFailure e1 <> AccFailure e2 =
    AccFailure (e1 <> e2)
  AccFailure _ <> AccSuccess a2  =
    AccSuccess a2
  AccSuccess a1  <> AccFailure _ =
    AccSuccess a1
  AccSuccess a1 <> AccSuccess _ =
    AccSuccess a1

instance Monoid e => Monoid (AccValidation e a) where
  AccFailure e1 `mappend` AccFailure e2 =
    AccFailure (e1 `mappend` e2)
  AccFailure _ `mappend` AccSuccess a2  =
    AccSuccess a2
  AccSuccess a1  `mappend` AccFailure _ =
    AccSuccess a1
  AccSuccess a1 `mappend` AccSuccess _ =
    AccSuccess a1
  mempty =
    AccFailure mempty

-- | A value of the type @err@ or @a@ and isomorphic to @Data.Either@.
data Validation err a =
  Failure err
  | Success a
  deriving (Eq, Ord, Show, Data, Typeable)

instance Functor (Validation err) where
  fmap _ (Failure e) = Failure e
  fmap f (Success a) = Success (f a)

instance Apply (Validation err) where
  Failure e1 <.> Failure _  =
    Failure e1
  Failure e1 <.> Success _  =
    Failure e1
  Success _  <.> Failure e2 =
    Failure e2
  Success f  <.> Success a  =
    Success (f a)

instance Applicative (Validation err) where
  pure =
    Success
  (<*>) =
    (<.>)

instance Alt (Validation err) where
  Failure _ <!> x =
    x
  Success a <!> _ =
    Success a

instance Monoid err => Alternative (Validation err) where
  Failure _ <|> x =
    x
  Success a <|> _ =
    Success a
  empty =
    Failure mempty

instance Foldable (Validation err) where
  foldr f x (Success a) =
    f a x
  foldr _ x (Failure _) =
    x

instance Traversable (Validation err) where
  traverse f (Success a) =
    Success <$> f a
  traverse _ (Failure e) =
    pure (Failure e)

instance Bifunctor Validation where
  bimap f _ (Failure e) =
    Failure (f e)
  bimap _ g (Success a) =
    Success (g a)

instance Bifoldable Validation where
  bifoldr _ g x (Success a) =
    g a x
  bifoldr f _ x (Failure e) =
    f e x

instance Bitraversable Validation where
  bitraverse _ g (Success a) =
    Success <$> g a
  bitraverse f _ (Failure e) =
    Failure <$> f e

instance Bind (Validation err) where
  Failure e >>- _ =
    Failure e
  Success a >>- f =
    f a

instance Monad (Validation err) where
  return =
    Success
  (>>=) =
    (>>-)

-- | The transformer version of @Validation@.
data ValidationT m err a =
  ValidationT {
    runValidationT :: m (Validation err a)
  }

instance Functor m => Functor (ValidationT m err) where
  fmap f (ValidationT k) =
    ValidationT (fmap (fmap f) k)

instance Apply m => Apply (ValidationT m err) where
  ValidationT f <.> ValidationT a =
    ValidationT (liftF2 (<.>) f a)

instance Applicative m => Applicative (ValidationT m err) where
  pure =
    ValidationT . pure . pure
  ValidationT f <*> ValidationT a =
    ValidationT (liftA2 (<*>) f a)

instance (Functor m, Monad m) => Alt (ValidationT m err) where
  ValidationT x <!> ValidationT y =
    ValidationT (x >>= \q -> case q of
      Failure _ -> y
      Success a -> return (Success a))

instance (Applicative m, Monad m, Monoid err) => Alternative (ValidationT m err) where
  ValidationT x <|> ValidationT y =
    ValidationT (x >>= \q -> case q of
      Failure _ -> y
      Success a -> return (Success a))
  empty =
    ValidationT (pure (Failure mempty))

instance Foldable m => Foldable (ValidationT m err) where
  foldr f z (ValidationT x) =
    foldr (flip (foldr f)) z x

instance Traversable m => Traversable (ValidationT m err) where
  traverse f (ValidationT x) =
      ValidationT <$> traverse (traverse f) x

instance Functor m => Bifunctor (ValidationT m) where
  bimap f g (ValidationT x) =
    ValidationT (fmap (bimap f g) x)

instance Foldable m => Bifoldable (ValidationT m) where
  bifoldr f g z (ValidationT x) =
    foldr (flip (bifoldr f g)) z x

instance Traversable m => Bitraversable (ValidationT m) where
  bitraverse f g (ValidationT x) =
    ValidationT <$> traverse (bitraverse f g) x

instance (Apply m, Monad m) => Bind (ValidationT m err) where
  ValidationT v >>- f =
    ValidationT (v >>= \w -> case w of
                               Failure e -> return (Failure e)
                               Success a -> runValidationT (f a))

instance Monad m => Monad (ValidationT m err) where
  return =
    ValidationT . return . pure
  ValidationT v >>= f =
    ValidationT (v >>= \w -> case w of
                               Failure e -> return (Failure e)
                               Success a -> runValidationT (f a))

-- | Construction for validation values.
class Validate v where
  -- | Construct a success validation value.
  success ::
    a
    -> v err a
  -- | Construct a failure validation value.
  failure ::
    err
    -> v err a

instance Validate AccValidation where
  failure =
    AccFailure
  success =
    AccSuccess

instance Validate Validation where
  failure =
    Failure
  success =
    Success

instance Applicative m => Validate (ValidationT m) where
  failure =
    ValidationT . pure . failure
  success =
    ValidationT . pure . success
