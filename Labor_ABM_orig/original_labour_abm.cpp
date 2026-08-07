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
#include <algorithm>

std::pair<std::vector<int>, std::vector<double>> run_simulation(
    int n_individuals, int n_firms, int n_steps,
    const std::vector<int>& worker_firm, const std::vector<double>& worker_res_wage, const std::vector<double>& worker_prod,
    const std::vector<double>& firm_desired, const std::vector<double>& firm_offered
) {
    std::vector<int> wf = worker_firm;
    std::vector<double> wrw = worker_res_wage;
    std::vector<double> firm_current_labor(n_firms, 0.0);

    for (int step = 0; step < n_steps; ++step) {
        // 1. Firing Phase
        std::fill(firm_current_labor.begin(), firm_current_labor.end(), 0.0);
        for (int i = 0; i < n_individuals; ++i) {
            int fid = wf[i];
            if (fid != -1) {
                firm_current_labor[fid] += worker_prod[i];
            }
        }

        for (int fid = 0; fid < n_firms; ++fid) {
            double excess = firm_current_labor[fid] - firm_desired[fid];
            if (excess > 0.0) {
                for (int i = 0; i < n_individuals; ++i) {
                    if (wf[i] == fid) {
                        excess -= worker_prod[i];
                        wf[i] = -1;
                        wrw[i] = std::max(10.0, wrw[i] * 0.9); // Decay reservation wage by 10% but not below 10.0
                        if (excess <= 0.0) {
                            break;
                        }
                    }
                }
            }
        }

        // Recompute current labor
        std::fill(firm_current_labor.begin(), firm_current_labor.end(), 0.0);
        for (int i = 0; i < n_individuals; ++i) {
            int fid = wf[i];
            if (fid != -1) {
                firm_current_labor[fid] += worker_prod[i];
            }
        }

        // 2. Hiring Phase
        for (int fid = 0; fid < n_firms; ++fid) {
            double needed = firm_desired[fid] - firm_current_labor[fid];
            if (needed > 0.0) {
                int hired_count = 0;
                for (int i = 0; i < n_individuals; ++i) {
                    if (wf[i] == -1) {
                        if (firm_offered[fid] >= wrw[i]) {
                            wf[i] = fid;
                            firm_current_labor[fid] += worker_prod[i];
                            needed -= worker_prod[i];
                            hired_count += 1;
                            wrw[i] = firm_offered[fid] * 1.05; // Increase reservation wage by 5% after being hired
                            if (needed <= 0.0 || hired_count >= 10) {
                                break;
                            }
                        }
                    }
                }
            }
        }

        // 3. Reservation wage decay for unemployed
        for (int i = 0; i < n_individuals; ++i) {
            if (wf[i] == -1) {
                wrw[i] = std::max(10.0, wrw[i] * 0.98); // Decay reservation wage by 2% but not below 10.0
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
    std::vector<int> worker_firm(n_individuals);
    std::vector<double> worker_res_wage(n_individuals);
    std::vector<double> worker_prod(n_individuals);
    
    // Pre-calculate divisors to avoid division by zero
    double ind_div = std::max(1.0, (double)(n_individuals - 1));
    
    for (int i = 0; i < n_individuals; ++i) {
        long long j = i + 1; // Shift index to match Julia's 1-based indexing for the math
        
        worker_firm[i] = (j % 100 < 15) ? -1 : ((j * 17) % n_firms);
        worker_res_wage[i] = 20.0 + ((j * 137) % n_individuals) / ind_div * 80.0;
        worker_prod[i] = 0.5 + ((j * 149) % n_individuals) / ind_div * 1.0;
    }

    std::vector<double> firm_desired(n_firms);
    std::vector<double> firm_offered(n_firms);
    
    double firm_div = std::max(1.0, (double)(n_firms - 1));
    
    for (int i = 0; i < n_firms; ++i) {
        long long j = i + 1;
        
        firm_desired[i] = 25.0 + ((j * 13) % n_firms) / firm_div * 40.0;
        firm_offered[i] = 15.0 + ((j * 19) % n_firms) / firm_div * 40.0;
    }

    std::cout << "Running C++ mini labor ABM simulation (" << n_individuals << " workers, " 
              << n_firms << " firms, " << n_steps << " steps)...\n";

    // Time starts after this comment so the Random Algorithms do NOT affect the Simulation time!--------------------------------------------------------------------------------------------------

    // Run and Benchmark Simulation
    auto start_time = std::chrono::high_resolution_clock::now();

    auto result = run_simulation(
        n_individuals, n_firms, n_steps,
        worker_firm, worker_res_wage, worker_prod,
         firm_desired, firm_offered
    );

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end_time - start_time;

    std::cout << "C++: Time = " << diff.count() << " seconds\n";

    // Calculate Final Metrics
    const auto& result_wf = result.first;
    const auto& result_wrw = result.second;

    int unemployed_count = 0;
    double sum_wage_unemployed = 0.0;
    double sum_wage_employed = 0.0;
    double total_active_labor = 0.0;

    for (int i = 0; i < n_individuals; ++i) {
        if (result_wf[i] == -1) {
            unemployed_count++;
            sum_wage_unemployed += result_wrw[i];
        } else {
            sum_wage_employed += result_wrw[i];
            total_active_labor += worker_prod[i];
        }
    }

    int employed_count = n_individuals - unemployed_count;
    
    double unemployment_rate = (static_cast<double>(unemployed_count) / n_individuals) * 100.0;
    double avg_wage_employed = employed_count > 0 ? (sum_wage_employed / employed_count) : 0.0;
    double avg_wage_unemployed = unemployed_count > 0 ? (sum_wage_unemployed / unemployed_count) : 0.0;
    
    double total_desired_labor = 0.0;
    for (int i = 0; i < n_firms; ++i) {
        total_desired_labor += firm_desired[i];
    }

    // Print Final Metrics
    std::cout << "\n==================================================\n";
    std::cout << "      FINAL SIMULATION METRICS (Step " << n_steps << ")\n";
    std::cout << "==================================================\n";
    std::cout << " Final Unemployment Rate                   : " << unemployment_rate << "%\n";
    std::cout << " Final Avg Reservation Wage (Employed)     : $" << avg_wage_employed << "\n";
    std::cout << " Final Avg Reservation Wage (Unemployed)   : $" << avg_wage_unemployed << "\n";
    std::cout << " Final Active Labor Units                  : " << (long long)total_active_labor << "\n";
    std::cout << " Target Desired Labor Demand               : " << (long long)total_desired_labor << "\n";
    std::cout << "==================================================\n\n";

    return 0;
}