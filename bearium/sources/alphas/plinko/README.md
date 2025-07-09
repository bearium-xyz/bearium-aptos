# Play Plinko On-Chain

**Plinko is timeless — a pure game of chance wrapped in a cascade of randomness.** Inspired by the iconic Pachinko and immortalized through decades of televised suspense, Plinko endures because it is simple, watchable, and scalable. Each drop is a discrete probabilistic journey — a ball navigating a triangular grid of pins toward a payout shaped by volatility.

In this on-chain implementation, we reimagine Plinko as a transparent, verifiable smart contract application — powered by **Aptos-native randomness** and governed by **math-first, before-fee multipliers**. Unlike traditional setups where house edge is hidden in the odds, this design decouples fees from gameplay, allowing multipliers to reflect pure expected value and enabling open economic modeling and predictable LP incentives.

With composable logic, customizable volatility, and provably fair outcomes, this Plinko is engineered not just to entertain — but to demonstrate how casino primitives can be made auditable, programmatic, and DeFi-aligned.

# Mechanics & Risk Modeling

Each round of Plinko simulates a ball descending through a triangular grid of pins. At every row, the ball bounces either left or right, representing an independent Bernoulli trial with uniform probability.

This traversal defines a classic **binomial process**, where:

- A **left bounce** is assigned value $0$
    
- A **right bounce** is assigned value $1$
    
- The final bin index corresponds to the count of right bounces accumulated across all $n$ rows

The outcome space consists of $n + 1$ bins, each corresponding to a unique count of right bounces $r \in [0, n]$. This allows us to compute the probability of landing in each bin deterministically.

## Ball Path as Binomial Distribution

Let:

$$
\begin{aligned}
n &= \text{number of rows (board depth)} \\
r &= \text{number of right bounces} \\
P &= \text{probability of right bounce per row (fixed at 0.5)} \\
p_r &= \text{probability of landing in bin } r
\end{aligned}
$$

Then the landing probability for each bin is defined by the **binomial distribution**:

$$
p_r = \binom{n}{r} \cdot P^r \cdot (1 - P)^{n - r}
$$

With $P=0.5$, this simplifies to:

$$
p_r = \binom{n}{r} \cdot (0.5)^n
$$

This distribution is symmetric around the center bin when $P=0.5$. For example, in a 16-row configuration, bin $8$ (the center) has the highest probability, while bins $0$ and $16$ (the outer edges) have the lowest — typically less than 0.002%.

This deterministic mapping allows us to precompute landing probabilities for every board configuration, enabling:

- Purely on-chain implementation
    
- Gas-efficient payout resolution
    
- Open and reproducible verification

## Bin Index to Payout Mapping

Each bin index $r$ is mapped to a **multiplier** from a predefined risk curve, configured by the game contract. These multipliers reflect a target **expected return** and are defined independently of any fees.

Since outcomes follow a known binomial distribution, the payout design can be shaped deterministically. For instance, edge bins (e.g., $r = 0$, $r = n$) may offer 1000× returns at extremely low probability, while central bins correspond to break-even or loss multipliers.

This mapping allows the volatility curve to be tunable per:

- **Risk Level** (e.g., Low / Medium / High)
    
- **Board Depth** ($n$ from 8 to 16)

This setup yields a fully composable and verifiable payout structure — one that mirrors real-world Plinko randomness while remaining mathematically tractable and economically programmable.
