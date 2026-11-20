/*
Author: Mael Ackermann
References:
1. Inspired by Axtell, R. L., & Farmer, J. D. (2025). Agent-Based Modeling in Economics and Finance: Past, Present, and Future.
    Journal of Economic Literature, 63(1), 197–287. https://doi.org/10.1257/jel.20221319
2. Inspired by the Oxford INET, macro-main model,
   URL: https://github.com/INET-Complexity/macro-main

Bounds-checking benchmark for the optimised C++ labour ABM.

The simulation is the optimised repository version. Two compile-time switches
select the variant, so all four C++ rows of the bounds-checking table come
from this one file:

  -DCHECKED      every indexed vector access uses v.at(i) (checked, throws
                 std::out_of_range) instead of v[i] (unchecked, as in the
                 repository version)
  -DINDEX_LOOPS  the loops over unemployed_indices use an index k, structured
                 like the Julia version, instead of the repository's range-for

Each variant runs one full-size warm-up, then N_REPS timed runs, and reports
median, min and max (as in bounds_check_benchmark.jl).

Build (same flags as in the paper):
  clang++ -O2 -march=native -mtune=native -flto -fuse-ld=lld -fno-math-errno                          bounds_check_benchmark.cpp -o bench_rf_unchecked.exe
  clang++ -O2 -march=native -mtune=native -flto -fuse-ld=lld -fno-math-errno -DCHECKED                bounds_check_benchmark.cpp -o bench_rf_checked.exe
  clang++ -O2 -march=native -mtune=native -flto -fuse-ld=lld -fno-math-errno -DINDEX_LOOPS            bounds_check_benchmark.cpp -o bench_idx_unchecked.exe
  clang++ -O2 -march=native -mtune=native -flto -fuse-ld=lld -fno-math-errno -DINDEX_LOOPS -DCHECKED  bounds_check_benchmark.cpp -o bench_idx_checked.exe
*/

#include <iostream>
#include <vector>
#include <chrono>
#include <algorithm>
#include <iomanip>
#include <stdexcept>

using namespace std;

#ifdef CHECKED
  #define IDX(v, i) (v).at(i)
  static const char* CHECK_MODE = "checked (.at() on every access)";
#else
  #define IDX(v, i) (v)[i]
  static const char* CHECK_MODE = "unchecked (operator[], up-front length checks only)";
#endif

#ifdef INDEX_LOOPS
  static const char* LOOP_MODE = "index loops (structured like the Julia version)";
#else
  static const char* LOOP_MODE = "range-for loops (repository version)";
#endif

static const int N_REPS = 10;

struct SimResult {
    vector<int> wf;
    vector<double> wrw;
};

SimResult run_simulation(
    int n_individuals, int n_firms, int n_steps,
    const vector<int>& worker_firm,
    const vector<double>& worker_res_wage,
    const vector<double>& worker_prod,
    const vector<double>& firm_desired,
    const vector<double>& firm_offered
) {
    // BOUNDARY CHECKS (unchanged from the repository version)
    if (worker_firm.size() != (size_t)n_individuals ||
        worker_res_wage.size() != (size_t)n_individuals ||
        worker_prod.size() != (size_t)n_individuals) {
        throw invalid_argument("CRITICAL ERROR: Individual vectors do not match n_individuals.");
    }
    if (firm_desired.size() != (size_t)n_firms ||
        firm_offered.size() != (size_t)n_firms) {
        throw invalid_argument("CRITICAL ERROR: Firm vectors do not match n_firms.");
    }

    vector<int> wf = worker_firm;
    vector<double> wrw = worker_res_wage;
    vector<double> firm_current_labor(n_firms, 0.0);
    vector<double> excess(n_firms, 0.0);
    vector<int> unemployed_indices;
    unemployed_indices.reserve(n_individuals);

    for (int step = 0; step < n_steps; ++step) {
        // 1. Compute current labor
        fill(firm_current_labor.begin(), firm_current_labor.end(), 0.0);
        for (int i = 0; i < n_individuals; ++i) {
            int fid = IDX(wf, i);
            if (fid != -1) IDX(firm_current_labor, fid) += IDX(worker_prod, i);
        }

        // Calculate excess labor per firm O(N_firms)
        for (int fid = 0; fid < n_firms; ++fid) {
            IDX(excess, fid) = IDX(firm_current_labor, fid) - IDX(firm_desired, fid);
        }

        // 2. Firing phase O(N_workers)
        for (int i = 0; i < n_individuals; ++i) {
            int fid = IDX(wf, i);
            if (fid != -1 && IDX(excess, fid) > 0.0) {
                IDX(excess, fid) -= IDX(worker_prod, i);
                IDX(firm_current_labor, fid) -= IDX(worker_prod, i);
                IDX(wf, i) = -1;
                IDX(wrw, i) = max(10.0, IDX(wrw, i) * 0.9);
            }
        }

        // Gather currently unemployed workers
        unemployed_indices.clear();
        for (int i = 0; i < n_individuals; ++i) {
            if (IDX(wf, i) == -1) unemployed_indices.push_back(i);
        }

        // 3. Hiring phase
        const int num_unemployed = (int)unemployed_indices.size();
        (void)num_unemployed;
        for (int fid = 0; fid < n_firms; ++fid) {
            double needed = IDX(firm_desired, fid) - IDX(firm_current_labor, fid);
            if (needed > 0.0) {
                double offered = IDX(firm_offered, fid);
                int hired_count = 0;
#ifdef INDEX_LOOPS
                for (int k = 0; k < num_unemployed; ++k) {
                    int i = IDX(unemployed_indices, k);
#else
                // Range-for: iterating the vector itself cannot go out of
                // bounds; only the indexing inside the loop is checked.
                for (int i : unemployed_indices) {
#endif
                    if (IDX(wf, i) == -1 && offered >= IDX(wrw, i)) {
                        IDX(wf, i) = fid;
                        IDX(firm_current_labor, fid) += IDX(worker_prod, i);
                        needed -= IDX(worker_prod, i);
                        hired_count++;
                        IDX(wrw, i) = offered * 1.05;
                        if (needed <= 0.0 || hired_count >= 10) break;
                    }
                }
            }
        }

        // 4. Reservation wage decay
#ifdef INDEX_LOOPS
        for (int k = 0; k < num_unemployed; ++k) {
            int i = IDX(unemployed_indices, k);
#else
        for (int i : unemployed_indices) {
#endif
            if (IDX(wf, i) == -1) {
                IDX(wrw, i) = max(10.0, IDX(wrw, i) * 0.98);
            }
        }
    }
    return {wf, wrw};
}

#ifdef CHECKED
// Proves that checking is really active: an out-of-range access must throw.
static bool bounds_checking_active() {
    vector<int> probe(10, 0);
    volatile int idx = 10;
    try { (void)IDX(probe, idx); }
    catch (const out_of_range&) { return true; }
    return false;
}
#endif

int main() {
    const int n_individuals = 100000;
    const int n_firms = 2000;
    const int n_steps = 110;

    // Deterministic initialisation, identical to the repository version
    vector<int> worker_firm(n_individuals);
    vector<double> worker_res_wage(n_individuals);
    vector<double> worker_prod(n_individuals);
    double ind_div = max(1.0, (double)(n_individuals - 1));
    for (int i = 0; i < n_individuals; ++i) {
        long long j = i + 1;
        worker_firm[i] = (j % 100 < 15) ? -1 : (int)((j * 17) % n_firms);
        worker_res_wage[i] = 20.0 + ((j * 137) % n_individuals) / ind_div * 80.0;
        worker_prod[i] = 0.5 + ((j * 149) % n_individuals) / ind_div * 1.0;
    }
    vector<double> firm_desired(n_firms);
    vector<double> firm_offered(n_firms);
    double firm_div = max(1.0, (double)(n_firms - 1));
    for (int i = 1; i <= n_firms; ++i) {
        firm_desired[i - 1] = 25.0 + ((i * 13) % n_firms) / firm_div * 40.0;
        firm_offered[i - 1] = 15.0 + ((i * 19) % n_firms) / firm_div * 40.0;
    }

    cout << "C++ bounds-check benchmark: " << n_individuals << " workers, " << n_firms
         << " firms, " << n_steps << " steps, " << N_REPS << " timed runs\n";
    cout << "Checks: " << CHECK_MODE << "\n";
    cout << "Loops:  " << LOOP_MODE << "\n";
#ifdef CHECKED
    cout << "Bounds checking verified active: " << (bounds_checking_active() ? "yes" : "NO") << "\n";
#endif

    auto run = [&]() {
        return run_simulation(n_individuals, n_firms, n_steps, worker_firm,
                              worker_res_wage, worker_prod, firm_desired, firm_offered);
    };

    SimResult result = run();  // warm-up (caches, page faults)

    vector<double> times;
    for (int r = 0; r < N_REPS; ++r) {
        auto t0 = chrono::steady_clock::now();
        result = run();
        auto t1 = chrono::steady_clock::now();
        times.push_back(chrono::duration<double>(t1 - t0).count());
    }
    vector<double> sorted = times;
    sort(sorted.begin(), sorted.end());
    double median = (N_REPS % 2 == 0)
        ? 0.5 * (sorted[N_REPS / 2 - 1] + sorted[N_REPS / 2])
        : sorted[N_REPS / 2];

    cout << fixed << setprecision(4);
    cout << "\nmedian [s]: " << median << "   min [s]: " << sorted.front()
         << "   max [s]: " << sorted.back() << "\n";

    // Metrics, to confirm both variants produce the same results
    int unemployed_count = 0;
    double sum_wage_unemployed = 0.0, total_active_labor = 0.0;
    for (int i = 0; i < n_individuals; ++i) {
        if (result.wf[i] == -1) { unemployed_count++; sum_wage_unemployed += result.wrw[i]; }
        else total_active_labor += worker_prod[i];
    }
    cout << setprecision(2);
    cout << "Unemployment: " << 100.0 * unemployed_count / n_individuals << "%"
         << "   Active labour: " << (long)total_active_labor
         << "   Avg unemployed res. wage: $" << sum_wage_unemployed / unemployed_count << "\n";
    return 0;
}
