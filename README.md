# Secure Recommendation Update System

**CS670: Cryptographic Techniques for Privacy Preservation**
Shubham Rawat (251110070)
Department of Computer Science and Engineering, IITK

| Directory | Assignment | Contents |
|---|---|---|
| [a1-mpc-rec-sys/](a1-mpc-rec-sys/) | 1 | Secure update of the **user** matrix `U` |
| [a2-dpf-gen/](a2-dpf-gen/) | 2 | Distributed Point Function generation and `EvalFull` testing |
| [a3-a4-item-update/](a3-a4-item-update/) | 3 and 4 | Secure update of the **item** matrix `V` using DPF, plus timing plots |

Each directory has its own `readme.pdf` — the report submitted for that
assignment. This file is the repository index and collects what is common to
all three.

Assignment 3 combines Assignment 1 and Assignment 2, so it keeps its own
modified copies of the A1 protocol files and the A2 DPF code. Each assignment
has to build and run on its own, so these copies are intentional.

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
ui ← ui + vj · δ           (Assignment 1)
vj ← vj + ui · δ           (Assignment 3)
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

Assignment 2 implements DPF generation and verifies it with `EvalFull`, which
evaluates both keys across the whole domain and checks that the shares
reconstruct the target value at the chosen index and zero elsewhere. The PRG
uses AES-128-ECB through OpenSSL EVP to expand a 128-bit seed into two child
seeds per level.

Assignment 3 keeps the same DPF logic, with these changes:

1. For the leaf nodes, instead of scalar values, they are converted into
   vectors of size equal to the row length of the item matrix.
2. The final correction word (FCW) is also changed to a vector.
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
| `src/dpf.hpp` *(A3 only)* | `DpfKey` structure, DPF generation and evaluation with vector leaves and FCW |

In Assignment 1 these sit in `parties/`, `dealer/`, `operationFunctions/` and
`generatorFunctions/`. In Assignment 3 they are under `src/`.

## Build and Run Commands

Assignment 1 and Assignment 3 both run through Docker:

```bash
cd a1-mpc-rec-sys          # or a3-a4-item-update
./runProtocol.sh           # prompts for users, items, features, queries
```

To build and run natively instead:

```bash
make all                   # -> generate.out dealer.out party0.out party1.out
make run_generate USERS=3 ITEMS=4 FEATURES=5
```

then in three separate terminals:

```bash
./dealer.out
./party0.out
./party1.out
```

Assignment 2 is standalone:

```bash
cd a2-dpf-gen
g++ -std=c++20 -O2 gen_queries.cpp -o gen_queries -lssl -lcrypto
./gen_queries
```

Requires `g++` with C++20, Boost.System and OpenSSL.

## Assignment 4 — Results

The time taken for the profile updates was measured while varying the number of
users, items and queries. The resulting plots are in
[a3-a4-item-update/plots/](a3-a4-item-update/plots/):

| Plot | Varies |
|---|---|
| `UserVsTime.png` | number of users |
| `Itemvquery.png` | number of items |
| `queryVsTime.png` | number of queries |

Timing is measured in `dealer.cpp` with `std::chrono::high_resolution_clock`,
which prints `Total execution time: N ms` at the end of a run.

## Known issues

- **`a2-dpf-gen/Dockerfile` does not build.** It compiles with
  `g++ -o gen_queries gen_queries.cpp` but installs only `libboost-all-dev`,
  while the source needs OpenSSL. The steps given in `a2-dpf-gen/readme.pdf` —
  `apt install libssl-dev` and `g++ gen_queries.cpp -o a -lssl -lcrypto` — are
  the correct ones; the Dockerfile just does not do either of them.
- `a2-dpf-gen/gen_queries.cpp` prompts for the DPF size and count on `stdin`,
  as described in its report. The A2 specification instead asks for them as
  arguments, `./gen_queries <DPF_size> <num_DPFs>`.
- In `a3-a4-item-update/src/`, `party0.cpp`, `party1.cpp` and `dealer.cpp`
  include `"../common.hpp"` although the file is at `src/common.hpp`. It only
  resolves because of the `-I./src/headerFiles` flag in the Makefile.
- `depends_on` in `docker-compose.yml` orders container start but does not wait
  for a listening socket, so a run can occasionally fail on connect. Re-run it.
