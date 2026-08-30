# Numerical Implementation

## FP64 Representation

The mathematical units operate on 64-bit IEEE-754 double-precision bit patterns.

The standard FP64 layout is:

```text
63        52 51                         0
+-----------+---------------------------+
| Sign (1)  | Exponent (11) | Fraction  |
+-----------+---------------------------+
```

The exponent bias is 1023.

## Polynomial Evaluation

Several transcendental and trigonometric functions use polynomial approximations evaluated with Horner's method.

For a polynomial:

```text
P(x) = C0 + C1*x + C2*x^2 + ... + Cn*x^n
```

Horner's form is:

```text
P(x) = (...((Cn*x + Cn-1)*x + Cn-2)*x ... + C0)
```

This structure reduces the number of explicit multiplications and provides a natural sequential FSM implementation.

## log2

The `log2` implementation decomposes a positive floating-point number into an exponent and normalized significand.

Conceptually:

```text
x = 2^e * m
```

with the significand normalized around one.

The implementation then evaluates the fractional logarithm using a polynomial approximation and combines it with the integer exponent:

```text
log2(x) = e + log2(m)
```

The current implementation uses a Taylor-series-derived coefficient set and Horner evaluation.

## ln

Natural logarithm is derived from base-2 logarithm:

```text
ln(x) = log2(x) * ln(2)
```

The `vrm_fpu_ln_64` module therefore reuses `vrm_fpu_log2_64` followed by the FP64 multiplier.

## exp2

The `exp2` implementation separates the input into an integer component and a fractional component:

```text
x = n + f
```

Then:

```text
2^x = 2^n * 2^f
```

The fractional component is approximated using a polynomial, while the integer component is represented as a power-of-two FP64 value.

The implementation uses a sequential FSM and reusable FP64 arithmetic blocks.

## exp

Natural exponential is derived from base-2 exponential:

```text
exp(x) = 2^(x * log2(e))
```

The implementation therefore consists conceptually of:

```text
x
 |
 v
multiply by log2(e)
 |
 v
exp2
 |
 v
result
```

## Sigmoid

The sigmoid function is implemented as:

```text
sigmoid(x) = 1 / (1 + exp(-x))
```

The datapath is:

```text
x
 |
 v
-x
 |
 v
exp()
 |
 v
1 + exp(-x)
 |
 v
1 / denominator
```

## Tanh

The hyperbolic tangent is implemented using:

```text
tanh(x) = (exp(2x) - 1) / (exp(2x) + 1)
```

The datapath computes `2x`, evaluates the exponential, then forms numerator and denominator before division.

## Sine

The sine implementation first computes:

```text
x2 = x * x
```

and evaluates an odd polynomial:

```text
sin(x) ≈ x * P(x²)
```

Horner evaluation is used for `P(x²)`.

## Cosine

The cosine implementation similarly computes:

```text
x2 = x * x
```

and evaluates an even polynomial:

```text
cos(x) ≈ P(x²)
```

The final polynomial result is directly returned.

## Numerical Accuracy

The transcendental and trigonometric functions are approximation-based implementations. Consequently, their results should be evaluated using numerical error metrics rather than exact hexadecimal equality for arbitrary inputs.

The current baseline test demonstrates exact results for several simple cases and small approximation errors for fractional transcendental cases.

A future verification extension should characterize:

- absolute error;
- relative error;
- maximum error;
- RMS error;
- valid input range;
- behavior near zero;
- behavior near overflow/underflow boundaries;
- IEEE-754 special values.
