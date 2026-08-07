/*
Author: Mael Ackermann
References:
1. Inspired by Axtell, R. L., & Farmer, J. D. (2025). Agent-Based Modeling in Economics and Finance: Past, Present, and Future. 
    Journal of Economic Literature, 63(1), 197–287. https://doi.org/10.1257/jel.20221319
2. Inspired by the Oxford INET, macro-main model,
   URL: https://github.com/INET-Complexity/macro-main
*/

#include <iostream>
#include <vector>
#include <chrono>
#include <cmath>
#include <algorithm>
#include <iomanip>

using namespace std;

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

    // BOUNDARY CHECKS
    if (worker_firm.size() != n_individuals || 
        worker_res_wage.size() != n_individuals || 
        worker_prod.size() != n_individuals) {
        throw std::invalid_argument("CRITICAL ERROR: Individual vectors do not match n_individuals.");
    }
    if (firm_desired.size() != n_firms || 
        firm_offered.size() != n_firms) {
        throw std::invalid_argument("CRITICAL ERROR: Firm vectors do not match n_firms.");
    }

    vector<int> wf = worker_firm;
    vector<double> wrw = worker_res_wage;
    
    vector<double> firm_current_labor(n_firms, 0.0);
    vector<double> excess(n_firms, 0.0);
    
    vector<int> unemployed_indices;
    unemployed_indices.reserve(n_individuals); // Prevent re-allocations

    for (int step = 0; step < n_steps; ++step) {
        // 1. Firing Phase
        fill(firm_current_labor.begin(), firm_current_labor.end(), 0.0);
        for (int i = 0; i < n_individuals; ++i) {
            int fid = wf[i];
            if (fid != -1) firm_current_labor[fid] += worker_prod[i];
        }

        // Calculate excess labor per firm O(N_firms)
        for (int fid = 0; fid < n_firms; ++fid) {
            excess[fid] = firm_current_labor[fid] - firm_desired[fid];
        }

        // (Reduced from O(N_firms * N_workers) to O(N_workers))
        for (int i = 0; i < n_individuals; ++i) {
            int fid = wf[i];
            if (fid != -1 && excess[fid] > 0.0) {
                excess[fid] -= worker_prod[i];
                firm_current_labor[fid] -= worker_prod[i];
                wf[i] = -1;
                wrw[i] = max(10.0, wrw[i] * 0.9); // Decay reservation wage by 10% but not below 10.0
            }
        }

        // Gather currently unemployed workers into a dense contiguous array
        unemployed_indices.clear();
        for (int i = 0; i < n_individuals; ++i) {
            if (wf[i] == -1) unemployed_indices.push_back(i);
        }

        // 3. Hiring Phase
        for (int fid = 0; fid < n_firms; ++fid) {
            double needed = firm_desired[fid] - firm_current_labor[fid];
            if (needed > 0.0) {
                double offered = firm_offered[fid];
                int hired_count = 0;
                for (int i : unemployed_indices) {
                    if (wf[i] == -1 && offered >= wrw[i]) {
                        wf[i] = fid;
                        firm_current_labor[fid] += worker_prod[i];
                        needed -= worker_prod[i];
                        hired_count++;
                        wrw[i] = offered * 1.05;
                        if (needed <= 0.0 || hired_count >= 10) break;
                    }
                }
            }
        }

        // 4. Reservation wage decay
        for (int i : unemployed_indices) {
            if (wf[i] == -1) {
                wrw[i] = max(10.0, wrw[i] * 0.98);
            }
        }
    }
    return {wf, wrw};
}

int main() {
    int n_individuals = 100000;
    int n_firms = 2000;
    int n_steps = 110;

    // Initialize arrays
    vector<int> worker_firm(n_individuals);
    vector<double> worker_res_wage(n_individuals);
    vector<double> worker_prod(n_individuals);
    
    // Pre-calculate divisors to avoid division by zero    
    double ind_div = max(1.0, (double)(n_individuals - 1));

    // Map the 1-indexed Julia setup to 0-indexed C++ identically
    for (int i = 0; i < n_individuals; ++i) {
        long long j = i + 1; // Shift index to match Julia's 1-based indexing for the math
        
        worker_firm[i] = (j % 100 < 15) ? -1 : ((j * 17) % n_firms);
        worker_res_wage[i] = 20.0 + ((j * 137) % n_individuals) / ind_div * 80.0;
        worker_prod[i] = 0.5 + ((j * 149) % n_individuals) / ind_div * 1.0;
    }

    vector<double> firm_desired(n_firms);
    vector<double> firm_offered(n_firms);
    double firm_div = max(1.0, (double)(n_firms - 1));

    for(int i = 1; i <= n_firms; ++i) {
        firm_desired[i-1] = 25.0 + ((i * 13) % n_firms) / firm_div * 40.0;
        firm_offered[i-1] = 15.0 + ((i * 19) % n_firms) / firm_div * 40.0;
    }

    std::cout << "Running C++ Optimized labour ABM simulation (" << n_individuals << " workers, " 
              << n_firms << " firms, " << n_steps << " steps)...\n";

    // Time starts after this comment so the Random Algorithms do NOT affect the Simulation time!--------------------------------------------------------------------------------------------------

    // Run and Benchmark Simulation
    auto start = chrono::high_resolution_clock::now();
    SimResult result = run_simulation(
        n_individuals, n_firms, n_steps,
        worker_firm, worker_res_wage, worker_prod,
        firm_desired, firm_offered
    );
    auto end = chrono::high_resolution_clock::now();
    chrono::duration<double> diff = end - start;
    
    cout << "C++: Time = " << diff.count() << " seconds\n";

    // Metrics Calculation
    int unemployed_count = 0;
    double sum_wage_unemployed = 0.0, sum_wage_employed = 0.0, total_active_labor = 0.0;

    for (int i = 0; i < n_individuals; ++i) {
        if (result.wf[i] == -1) {
            unemployed_count++;
            sum_wage_unemployed += result.wrw[i];
        } else {
            sum_wage_employed += result.wrw[i];
            total_active_labor += worker_prod[i];
        }
    }

    int employed_count = n_individuals - unemployed_count;
    double unemployment_rate = ((double)unemployed_count / n_individuals) * 100.0;
    double avg_wage_employed = employed_count > 0 ? (sum_wage_employed / employed_count) : 0.0;
    double avg_wage_unemployed = unemployed_count > 0 ? (sum_wage_unemployed / unemployed_count) : 0.0;
    
    double total_desired_labor = 0.0;
    for (double desired : firm_desired) total_desired_labor += desired;

    cout << fixed << setprecision(2);
    cout << "\n==================================================\n";
    cout << "      FINAL SIMULATION METRICS (Step " << n_steps << ")\n";
    cout << "==================================================\n";
    cout << " Final Unemployment Rate                  : " << unemployment_rate << "%\n";
    cout << " Final Avg Reservation Wage (Employed)    : $" << avg_wage_employed << "\n";
    cout << " Final Avg Reservation Wage (Unemployed)  : $" << avg_wage_unemployed << "\n";
    cout << " Final Active Labor Units                 : " << (long)total_active_labor << "\n";
    cout << " Target Desired Labor Demand              : " << (long)total_desired_labor << "\n";
    cout << "==================================================\n";

    return 0;
}