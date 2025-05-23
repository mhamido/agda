..
  ::
  module language.telescopes where

  open import Agda.Builtin.Bool
  open import Agda.Builtin.Nat

  postulate
    List : Set → Set
    _++_ : {A : Set} → List A → List A → List A
    Vec : Set → Nat → Set
    IsTrue : Bool → Set
    Monoid : Set → Set
    NonZero : Nat → Set

  record _×_ (A B : Set) : Set where
    constructor _,_
    field
      fst : A
      snd : B

.. _telescopes:

**********
Telescopes
**********

A telescope is a non-empty sequence of variable bindings annotated by their types,
with each variable surrounded by parentheses.
For example, ``(x : Nat) (y : Bool) (z : Bool)`` is a telescope.
Adjacent variables that have the same type can share a type annotation.
For example, the same telescope can be written equivalently as ``(x : Nat) (y z : Bool)``.
The type of each variable can depend on the previous variables in the telescope,
for example ``(A : Set) (n : Nat) (v : Vec A n)``.

.. note::
  The terminology is due to de Bruijn :ref:`[1] <telescopes-refs>`:
  "The word was inspired, of course, by the old-fashioned instrument consisting of segments that slide one into another."
  Each variable binding corresponds to a segment of the telescope, which can slide into (i.e. depend on) the previous ones.

Telescopes appear in the following parts of the Agda syntax:

* :ref:`Function types<function-types>`
* Declarations of :ref:`data types<data-types>` and :ref:`record types<record-types>`
* Declarations of :ref:`parameterised modules <parameterised-modules>`

::

  postulate
    f : (A : Set) (n : Nat) (v : Vec A n) → Nat

  data D (A : Set) (n : Nat) (v : Vec A n) : Set where
    -- ...

  module M (A : Set) (n : Nat) (v : Vec A n) where
    -- ...


In telescopes of data and record types as well as parameterised modules,
it is allowed to omit the type of a variable binding. This is equivalent
to giving the variable the type ``_`` (see :ref:`implicit arguments<implicit-arguments>`).

::

  data D' A n (v : Vec A n) : Set where
    -- ...

  module M' A n (v : Vec A n) where
    -- ...

In function types, the type of a variable binding can be omitted if the module telescope
starts with ``forall`` or ``∀``.

::

  postulate
    f' : ∀ A n (v : Vec A n) → Nat

When binding a variable of a :ref:`record type<record-types>` (but not a data type),
it is possible to deconstruct the bound variable by :ref:`pattern matching<decomposing-records>`:

::

  module N ((x , y) : Nat × Bool) where
    -- ...

Variable bindings in a telescope can be :ref:`implicit <implicit-arguments>` or :ref:`instance
<instance-arguments>` arguments. For example:

::

  postulate
    mconcat : {A : Set} {{monoidA : Monoid A}} → List A → A

They can also be
:ref:`irrelevant <irrelevance>` or carry another :ref:`modality <modalities>`.
For example:

::

  postulate
    div : (m n : Nat) .(nz : NonZero n) → Nat


Irrefutable Patterns in Binding Positions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

..
  ::
  module pattern-tele where
    open import Agda.Builtin.Sigma
    open import Agda.Builtin.Equality
    private
      variable
        A : Set
        B : A → Set

Since Agda 2.6.1, irrefutable patterns can be used at every binding site in a
telescope to take the bound value of record type apart. The type of the second
projection out of a dependent pair will for instance naturally mention the value
of the first projection. Its type can be defined directly using an irrefutable
pattern as follows:

::

    proj₂ : ((a , _) : Σ A B) → B a

And this second projection can be implemented with a lamba-abstraction using
one of these irrefutable patterns taking the pair apart:

::

    proj₂ = λ (_ , b) → b

Using an as-pattern makes it possible to name the argument and to take it
apart at the same time. We can for instance prove that any pair is equal
to the pairing of its first and second projections, a property commonly
called eta-equality:

::

    eta : (p@(a , b) : Σ A B) → p ≡ (a , b)
    eta p = refl


Let Bindings in Telescopes
~~~~~~~~~~~~~~~~~~~~~~~~~~

..
  ::
  module let-bind-in-tele where


Telescopes of function types and parameterised modules (but not of data and record types) can also contain :ref:`let bindings<let-expressions>`.
When used in this manner, the let-binding should be surrounded by parentheses
and the ``in`` part of the syntax is omitted. For example:

::

  postulate
    g : (x : Nat) (let y = x + x) (v : Vec Nat y) → Nat

Let-bound variables in a module telescope are available in the whole module. For example:

::

  module O (X : Set) (let LX = List X) (l : LX) where

    extend : LX → LX
    extend m = l ++ m

In general, any valid let-binding can also be used in a telescope.
For example, it is possible to pattern match on a record type with a let-binding:

::

  postulate
    h : (f : Nat → (Bool × Bool)) (let (x0 , y0) = f 0) (tx : IsTrue x0) → IsTrue y0

Another notable example is opening a :ref:`module<module-system>` in a telescope:

::

  module M1 (X : Set) (let open M X) where

This can also be written more compactly with just ``open`` (without the ``let``):

::

  module M2 (X : Set) (open M X) where

.. _telescopes-refs:

References
==========

[1] N.G. de Bruijn. "`Telescopic mappings in typed lambda calculus. <https://doi.org/10.1016/0890-5401(91)90066-B>`_"
Information and Computation, Volume 91, Issue 2, 1991.
