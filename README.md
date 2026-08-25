# Secure Recommendation Update System

**CS670: Cryptographic Techniques for Privacy Preservation**
Shubham Rawat (251110070)
Department of Computer Science and Engineering, IITK

A two-party secure multi-party computation (MPC) system that updates a
recommendation engine's latent user and item profiles after a query, without
either party ever seeing a profile in the clear — or, for item updates,
learning which item was queried.

A recommendation system holds user profiles `U ∈ Z^{m×k}` and item profiles
`V ∈ Z^{n×k}`. A prediction is `r̂ᵢⱼ = ⟨uᵢ, vⱼ⟩`. After a query `(i, j)`, both
profiles move toward each other:

```
δ  = 1 − ⟨ui, vj⟩
ui ← ui + vj · δ        (user-profile update)
vj ← vj + ui · δ        (item-profile update)
```

`U` and `V` are additively secret-shared between two servers `S0`, `S1`, and
neither may learn either matrix. The item update is the harder of the two:
the servers hold `V` but don't know which row `j` to touch, and the user knows
`j` but can't compute the update value without a share of `V`. That's solved
with a Distributed Point Function (DPF), described below.

---

## Secret Sharing Implementation

The matrices `U` and `V` are split into additive shares between two parties
`S0` and `S1`:

```
U = U0 + U1        V = V0 + V1
```

Each party stores its own share locally and never reveals it to the other.

To update user `i`, the protocol needs two values:

- The user index `i` — public.
- The item index `j` — private.

The item index is represented as a secret-shared standard basis vector of size
equal to the number of items. This enables privately selecting `vj` during MPC.

Once shares of both `ui` and `vj` are obtained:

```
δ  = 1 − ⟨ui, vj⟩          (1 is also secret shared between the parties)
ui ← ui + vj · δ
vj ← vj + ui · δ
```

All multiplications — vector–scalar, vector–vector, and vector–matrix — use
Beaver triplets.

## MPC Inner Product and Updates

### Secure Dot Product

To compute `⟨ui, vj⟩` securely:

1. A trusted dealer sends Beaver triplet shares to both parties.
2. Using the triplet shares, each party computes blinded values and exchanges
   them with the other.
3. After local computation, each party gets its share of the multiplication.

Each party updates its own share locally. The operations are performed using
only the local shares and MPC communication.

## Distributed Point Function

For the item-profile update, the servers must apply the update at row `j`
without learning `j`. This is done with a DPF: two keys `(k0, k1)` such that
evaluating each key across the whole domain and XOR-ing the results gives the
target value at index `j` and zero everywhere else.

`EvalFull` verifies this by evaluating both keys and checking the
reconstruction. The PRG uses AES-128-ECB through OpenSSL EVP to expand a
128-bit seed into two child seeds per tree level.

For the item update, the DPF is extended:

1. Leaf nodes hold vectors, of size equal to the row length of the item
   matrix, instead of scalars.
2. The final correction word (FCW) is also a vector.
3. The correction words are computed as:

   ```
   FCW1 = prgVector(dist(genValue), k)          (a random vector)
   FCW0 = leafVecAtTarget0 − leafVecAtTarget1 − FCW1
   ```

4. Both parties exchange masked values — `M0 − FCW0` from Party 0 and
   `M1 − FCW1` from Party 1 — then each computes:

   ```
   fcwm = (M0 − FCW0) + (M1 − FCW1) = M − FCW
   ```

5. One party multiplies the leaf value by −1 and applies the final correction
   word based on the flag bits, as per the DPF definition.
6. At the target index, applying the correction on Party 0 gives `M0 + v1`,
   and Party 1 outputs `−v1`, so the reconstruction is
   `(M0 + v1) + (−v1) = M`.

This is what lets the servers apply the update at index `j` without learning
`j`, and without the user knowing the update value `M`.

## Communication and Efficiency

- The dealer sends Beaver triplets, shares of 1, and standard vector shares to
  both parties.
- Party0 and Party1 exchange blinded values three times:
  - Blind 1 — for computing `vj`
  - Blind 2 — for computing `⟨ui, vj⟩`
  - Blind 3 — for the multiplication by `δ`
- C++ coroutines (`boost::asio`) are used to handle party communication
  asynchronously.

The dealer listens on port **9002**. Party0 also listens on **9003** for the
peer connection from Party1. Under Docker the parties reach each other by
Compose service name (`dealer`, `party0`).

## Code Structure

| File | Purpose |
|---|---|
| `headerFiles/gen_queries.h` | Structure definitions for secret shares and Beaver triplets: `LatentVector`, `LatentVectorShares`, `StandardVectorShares`, `VectorTriplet`/`VectorTripletShares`, `ScalarandVectorTriplet`/`ScalarandVectorTripletShares`, `MatrixVectorTriplet`/`MatrixVectorTripletShare` |
| `generatorFunctions/gen_queries.cpp` | Generates the Beaver triplets and shared vectors declared above |
| `headerFiles/mpcOperations.h` | Declarations for the MPC multiplication functions |
| `mpcMultiplication.cpp` | Beaver-triplet multiplication: vector–vector, vector–scalar, vector–matrix |
| `generatorFunctions/saveToFile.cpp` | Builds `U` and `V`, writes the share files |
| `dealer.cpp` | Coordinates MPC, sends triplets, reconstructs results |
| `party0.cpp`, `party1.cpp` | Perform the MPC steps and communicate |
| `common.hpp` | Coroutine-based network utilities (send/recv for ints, vectors, matrices) |
| `src/dpf.hpp` *(item-update module only)* | `DpfKey` structure, DPF generation and evaluation with vector leaves and FCW |

In the user-update module these sit in `parties/`, `dealer/`,
`operationFunctions/` and `generatorFunctions/`. In the item-update module
they are under `src/`.

## Benchmarks

The time taken for a profile update was measured while varying the number of
users, items and queries. The resulting plots are in
[a3-a4-item-update/plots/](a3-a4-item-update/plots/):

| Plot | Varies |
|---|---|
| `UserVsTime.png` | number of users |
| `Itemvquery.png` | number of items |
| `queryVsTime.png` | number of queries |

Timing is measured in `dealer.cpp` with `std::chrono::high_resolution_clock`,
which prints `Total execution time: N ms` at the end of a run.

## Running

Both modules are launched with `./runProtocol.sh` from their own directory,
which prompts for the parameters and brings up Docker Compose. Full build and
run instructions are in each module's own report:

| Module | What it does | Report |
|---|---|---|
| [a1-mpc-rec-sys/](a1-mpc-rec-sys/) | Secure user-profile update | [readme.pdf](a1-mpc-rec-sys/readme.pdf) |
| [a2-dpf-gen/](a2-dpf-gen/) | DPF generation and `EvalFull` testing | [readme.pdf](a2-dpf-gen/readme.pdf) |
| [a3-a4-item-update/](a3-a4-item-update/) | Secure item-profile update (DPF + MPC), with benchmarks | [readme.pdf](a3-a4-item-update/readme.pdf) |

---

## Repository layout

This system was built up across coursework submissions, so the module
directories are still named after them. `a3-a4-item-update/` combines the
user-update protocol and the DPF generator, and keeps its own modified copies
of that code rather than importing it — each module has to build and run on
its own.
