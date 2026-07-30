# Wide tables crash the Gleam compiler

Found while running gitlab's `structure.sql` through glsql. Not a glsql bug,
but glsql output triggers it, so it is a real limit on how wide a table can be.

## What happens

`gleam build` dies with a segfault (exit 139) on a table wider than 142
columns. glsql writes one `use` per column in `decoder()`, and the compiler
runs out of stack on the nested chain.

Gitlab's `application_settings` has 582 columns, so it crashes. It was the only
table out of 1421 that did.

## It is the compiler, not glsql

The generated Erlang is never written, so the crash is in gleam's own pass,
before it hands anything to `erlc`.

Nothing glsql-specific is needed to reproduce it. This file alone is enough,
with no dependencies:

```gleam
fn step(k: fn(Int) -> a) -> a {
  k(1)
}

pub fn main() -> Int {
  use a1 <- step
  use a2 <- step
  // ... 143 of these
  a1
}
```

Generate it with:

```sh
{ echo "fn step(k: fn(Int) -> a) -> a {"; echo "  k(1)"; echo "}"; echo ""
  echo "pub fn main() -> Int {"
  for i in $(seq 1 143); do echo "  use a$i <- step"; done
  echo "  a1"; echo "}"; } > src/usechain.gleam
```

## Numbers

Measured on gleam 1.17.0, linux (WSL2).

- 142 nested `use`: compiles
- 143 nested `use`: segfault

Same boundary for the hand written chain and for a glsql generated decoder, so
the column count and the `use` count line up exactly.

Dropping just the `decoder()` function from a 200 column module makes it
compile, so the wide record type and `to_params` are fine. Only the `use` chain
matters.

## It is a stack overflow

From dmesg:

```
gleam[72712]: segfault at 75e656d66f58 ip 000075e657d7421d sp 000075e656d66e50 error 6
```

The faulting address is 264 bytes past the stack pointer, and error 6 is a
write to an unmapped page. That is a guard page hit.

## No way to work around it

The boundary stays at 143 with all of these:

- `ulimit -s unlimited`
- `RUST_MIN_STACK` at 64MB, 256MB and 1GB
- both together

So the pass runs on a thread whose stack size is fixed in the compiler and does
not read `RUST_MIN_STACK`. Worth reporting upstream with the repro above.

## What to tell users meanwhile

A table wider than 142 columns cannot have a generated decoder that compiles.
Nothing glsql can do about the depth, since writing the closures out by hand
nests just as deeply.
