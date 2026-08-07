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
#include <fstream>
#include <string>

// Data structures added for plotting
struct SimulationHistory {
    std::vector<double> unemployment_rate;
    std::vector<double> avg_wage_employed;
    std::vector<double> avg_wage_unemployed;
    std::vector<double> total_labor;
    double total_desired_labor;
    std::vector<double> initial_wrw;
    std::vector<double> final_wrw;
};

struct SimulationResult {
    std::vector<int> final_wf;
    std::vector<double> final_wrw;
    SimulationHistory history;
};

SimulationResult run_simulation(
    int n_individuals, int n_firms, int n_steps,
    const std::vector<int>& worker_firm, const std::vector<double>& worker_res_wage, const std::vector<double>& worker_prod,
    const std::vector<double>& firm_desired, const std::vector<double>& firm_offered
) {
    std::vector<int> wf = worker_firm;
    std::vector<double> wrw = worker_res_wage;
    std::vector<double> firm_current_labor(n_firms, 0.0);

    // Initialize history arrays
    SimulationHistory history;
    history.unemployment_rate.resize(n_steps);
    history.avg_wage_employed.resize(n_steps);
    history.avg_wage_unemployed.resize(n_steps);
    history.total_labor.resize(n_steps);
    history.initial_wrw = worker_res_wage;

    double sum_desired = 0.0;
    for (double d : firm_desired) sum_desired += d;
    history.total_desired_labor = sum_desired;

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

        // 4. Metrics Collection per step (Appended for plotting)
        int unemp_cnt = 0;
        int emp_cnt = 0;
        double sum_w_unemp = 0.0;
        double sum_w_emp = 0.0;

        for (int i = 0; i < n_individuals; ++i) {
            if (wf[i] == -1) {
                unemp_cnt++;
                sum_w_unemp += wrw[i];
            } else {
                emp_cnt++;
                sum_w_emp += wrw[i];
            }
        }

        history.unemployment_rate[step] = (static_cast<double>(unemp_cnt) / n_individuals) * 100.0;
        history.avg_wage_unemployed[step] = unemp_cnt > 0 ? sum_w_unemp / unemp_cnt : 0.0;
        history.avg_wage_employed[step] = emp_cnt > 0 ? sum_w_emp / emp_cnt : 0.0;
        
        double current_total_labor = 0.0;
        for(int fid = 0; fid < n_firms; ++fid) {
            current_total_labor += firm_current_labor[fid];
        }
        history.total_labor[step] = current_total_labor;
    }

    history.final_wrw = wrw;

    return {wf, wrw, history};
}

// Helpers for Plotly JS arrays
void print_js_array(std::ofstream& out, const std::string& name, const std::vector<double>& v) {
    out << "var " << name << " = [";
    for(size_t i = 0; i < v.size(); ++i) {
        out << v[i];
        if(i != v.size() - 1) out << ",";
    }
    out << "];\n";
}

void generate_html_report(const SimulationHistory& history, const std::string& filename) {
    std::ofstream out(filename);
    
    out << R"(
<!DOCTYPE html>
<html>
<head>
    <title>C++ Simulation Dashboard</title>
    <script src="https://cdn.plot.ly/plotly-2.24.1.min.js"></script>
    <style>
        body { font-family: sans-serif; background: #f8f9fa; margin: 0; padding: 20px; }
        .grid-container {
            display: grid;
            grid-template-columns: 1fr 1fr;
            grid-gap: 20px;
            max-width: 1200px;
            margin: 0 auto;
        }
        .plot-container { background: white; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); padding: 10px; }
        .plot { width: 100%; height: 400px; }
        h1 { text-align: center; color: #333; margin-bottom: 30px; }
    </style>
</head>
<body>
    <h1>C++ ABM Simulation Results</h1>
    <div class="grid-container">
        <div class="plot-container"><div id="plot1" class="plot"></div></div>
        <div class="plot-container"><div id="plot2" class="plot"></div></div>
        <div class="plot-container"><div id="plot3" class="plot"></div></div>
        <div class="plot-container"><div id="plot4" class="plot"></div></div>
    </div>
    <script>
)";

    std::vector<double> steps(history.unemployment_rate.size());
    for(size_t i=0; i<steps.size(); ++i) steps[i] = static_cast<double>(i+1);

    print_js_array(out, "steps", steps);
    print_js_array(out, "unemp", history.unemployment_rate);
    print_js_array(out, "wage_emp", history.avg_wage_employed);
    print_js_array(out, "wage_unemp", history.avg_wage_unemployed);
    print_js_array(out, "labor", history.total_labor);
    print_js_array(out, "initial_wrw", history.initial_wrw);
    print_js_array(out, "final_wrw", history.final_wrw);
    
    out << "var desired_labor = " << history.total_desired_labor << ";\n";

    out << R"(
// Plot 1
Plotly.newPlot('plot1', [{
    x: steps, y: unemp, type: 'scatter', mode: 'lines', name: 'Unemployment (%)', line: {color: 'crimson', width: 2}
}], {
    title: 'Unemployment Rate (%)',
    hovermode: 'x unified',
    xaxis: {title: 'Step', showgrid: true}, yaxis: {title: 'Unemployment (%)', showgrid: true},
    showlegend: false,
    annotations: [{ x: steps.length * 0.7, y: unemp[unemp.length-1]+1.2, text: 'Final: '+unemp[unemp.length-1].toFixed(2)+'%', showarrow: false, font: {color: 'darkred'} }]
});

// Plot 2
Plotly.newPlot('plot2', [
    {x: steps, y: wage_emp, type: 'scatter', mode: 'lines', name: 'Employed', line: {color: 'navy', width: 2}},
    {x: steps, y: wage_unemp, type: 'scatter', mode: 'lines', name: 'Unemployed', line: {color: 'orange', width: 2}}
], {
    title: 'Avg Reservation Wage',
    hovermode: 'x unified',
    xaxis: {title: 'Step', showgrid: true}, yaxis: {title: 'Wage (USD)', showgrid: true},
    legend: {orientation: 'v', x: 1.05, y: 1}
});

// Plot 3
Plotly.newPlot('plot3', [
    {x: steps, y: labor, type: 'scatter', mode: 'lines', name: 'Active Labor Supply', line: {color: 'teal', width: 2}},
    {x: [steps[0], steps[steps.length-1]], y: [desired_labor, desired_labor], type: 'scatter', mode: 'lines', name: 'Desired Demand Target', line: {color: 'firebrick', width: 2, dash: 'dash'}}
], {
    title: 'Labor Utilization vs Demand Target',
    hovermode: 'x unified',
    xaxis: {title: 'Step', showgrid: true}, yaxis: {title: 'Labor Units', showgrid: true},
    legend: {orientation: 'v', x: 1.05, y: 1}
});

// Plot 4
Plotly.newPlot('plot4', [
    {x: initial_wrw, type: 'histogram', name: 'Initial (Step 0)', marker: {color: 'royalblue'}, opacity: 0.5, nbinsx: 35},
)";
    out << "    {x: final_wrw, type: 'histogram', name: 'Final (Step " << history.unemployment_rate.size() << ")', marker: {color: 'coral'}, opacity: 0.5, nbinsx: 35}\n";
    out << R"(], {
    title: 'Reservation Wage Distribution Shift',
    barmode: 'overlay',
    xaxis: {title: 'Wage (USD)', showgrid: true}, yaxis: {title: 'Worker Count', showgrid: true},
    legend: {orientation: 'v', x: 1.05, y: 1}
});
    </script>
</body>
</html>
)";
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

    // Print Final Metrics directly from the captured history
    auto& h = result.history;

    std::cout << "\n==================================================\n";
    std::cout << "      FINAL SIMULATION METRICS (Step " << n_steps << ")\n";
    std::cout << "==================================================\n";
    std::cout << " Final Unemployment Rate                   : " << h.unemployment_rate.back() << "%\n";
    std::cout << " Final Avg Reservation Wage (Employed)     : $" << h.avg_wage_employed.back() << "\n";
    std::cout << " Final Avg Reservation Wage (Unemployed)   : $" << h.avg_wage_unemployed.back() << "\n";
    std::cout << " Final Active Labor Units                  : " << (long long)h.total_labor.back() << "\n";
    std::cout << " Target Desired Labor Demand               : " << (long long)h.total_desired_labor << "\n";
    std::cout << "==================================================\n\n";

    std::string html_file = "simulation_results_cpp.html";
    std::cout << "Generating interactive HTML dashboard (" << html_file << ")...\n";
    generate_html_report(h, html_file);
    std::cout << "Plot saved successfully to '" << html_file << "'.\n";

    return 0;
}