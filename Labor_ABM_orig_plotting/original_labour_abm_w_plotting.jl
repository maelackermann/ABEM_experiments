#=
Author: Mael Ackermann
References:
1. Inspired by Axtell, R. L., & Farmer, J. D. (2025). Agent-Based Modeling in Economics and Finance: Past, Present, and Future. 
   Journal of Economic Literature, 63(1), 197–287. https://doi.org/10.1257/jel.20221319
2. Inspired by the Oxford INET, macro-main model,
   URL: https://github.com/INET-Complexity/macro-main
=#

using Random

function run_simulation(
    n_individuals, n_firms, n_steps,
    worker_firm, worker_res_wage, worker_prod,
    firm_desired, firm_offered
)
    # Standard array copying
    wf = copy(worker_firm)
    wrw = copy(worker_res_wage)
    firm_current_labor = zeros(Float64, n_firms)

    # Time-series history metrics for plotting
    unemployment_rate = Vector{Float64}(undef, n_steps)
    avg_wage_employed = Vector{Float64}(undef, n_steps)
    avg_wage_unemployed = Vector{Float64}(undef, n_steps)
    total_labor = Vector{Float64}(undef, n_steps)

    for step in 1:n_steps
        # 1. Firing Phase
        fill!(firm_current_labor, 0.0)
        for i in 1:n_individuals
            fid = wf[i]
            if fid != -1
                firm_current_labor[fid + 1] += worker_prod[i]
            end
        end

        for fid in 0:(n_firms - 1)
            excess = firm_current_labor[fid + 1] - firm_desired[fid + 1]
            if excess > 0.0
                for i in 1:n_individuals
                    if wf[i] == fid
                        excess -= worker_prod[i]
                        wf[i] = -1
                        wrw[i] = max(10.0, wrw[i] * 0.9) # Decay reservation wage by 10% but not below 10.0
                        if excess <= 0.0
                            break
                        end
                    end
                end
            end
        end

        # Recompute current labor
        fill!(firm_current_labor, 0.0)
        for i in 1:n_individuals
            fid = wf[i]
            if fid != -1
                firm_current_labor[fid + 1] += worker_prod[i]
            end
        end

        # 2. Hiring Phase
        for fid in 0:(n_firms - 1)
            needed = firm_desired[fid + 1] - firm_current_labor[fid + 1]
            if needed > 0.0
                hired_count = 0
                for i in 1:n_individuals
                    if wf[i] == -1
                        if firm_offered[fid + 1] >= wrw[i]
                            wf[i] = fid
                            firm_current_labor[fid + 1] += worker_prod[i]
                            needed -= worker_prod[i]
                            hired_count += 1
                            wrw[i] = firm_offered[fid + 1] * 1.05 # Increase reservation wage by 5% after being hired
                            if needed <= 0.0 || hired_count >= 10
                                break
                            end
                        end
                    end
                end
            end
        end

        # 3. Reservation wage decay for unemployed
        for i in 1:n_individuals
            if wf[i] == -1
                wrw[i] = max(10.0, wrw[i] * 0.98) # Decay reservation wage by 2% but not below 10.0
            end
        end

        # 4. Metrics Collection per step for plotting
        unemp_cnt = 0
        emp_cnt = 0
        sum_w_unemp = 0.0
        sum_w_emp = 0.0

        for i in 1:n_individuals
            if wf[i] == -1
                unemp_cnt += 1
                sum_w_unemp += wrw[i]
            else
                emp_cnt += 1
                sum_w_emp += wrw[i]
            end
        end

        unemployment_rate[step] = (unemp_cnt / n_individuals) * 100.0
        avg_wage_unemployed[step] = unemp_cnt > 0 ? sum_w_unemp / unemp_cnt : 0.0
        avg_wage_employed[step] = emp_cnt > 0 ? sum_w_emp / emp_cnt : 0.0
        total_labor[step] = sum(firm_current_labor)
    end

    history = (
        unemployment_rate = unemployment_rate,
        avg_wage_employed = avg_wage_employed,
        avg_wage_unemployed = avg_wage_unemployed,
        total_labor = total_labor,
        total_desired_labor = sum(firm_desired)
    )

    return wf, wrw, history
end

# Helpers for plotting
function vec_to_js(v)
    io = IOBuffer()
    write(io, "[")
    for (i, val) in enumerate(v)
        write(io, string(val))
        if i < length(v)
            write(io, ",")
        end
    end
    write(io, "]")
    return String(take!(io))
end

function plot_simulation_results(history, initial_wrw, final_wrw; filename="simulation_results.html")
    n_steps = length(history.unemployment_rate)
    steps = collect(1:n_steps)
    
    html = """
<!DOCTYPE html>
<html>
<head>
    <title>Julia Simulation Dashboard</title>
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
    <h1>Julia ABM Simulation Results</h1>
    <div class="grid-container">
        <div class="plot-container"><div id="plot1" class="plot"></div></div>
        <div class="plot-container"><div id="plot2" class="plot"></div></div>
        <div class="plot-container"><div id="plot3" class="plot"></div></div>
        <div class="plot-container"><div id="plot4" class="plot"></div></div>
    </div>
    <script>
var steps = $(vec_to_js(steps));
var unemp = $(vec_to_js(history.unemployment_rate));
var wage_emp = $(vec_to_js(history.avg_wage_employed));
var wage_unemp = $(vec_to_js(history.avg_wage_unemployed));
var labor = $(vec_to_js(history.total_labor));
var initial_wrw = $(vec_to_js(initial_wrw));
var final_wrw = $(vec_to_js(final_wrw));
var desired_labor = $(history.total_desired_labor);

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
    {x: final_wrw, type: 'histogram', name: 'Final (Step $(n_steps))', marker: {color: 'coral'}, opacity: 0.5, nbinsx: 35}
], {
    title: 'Reservation Wage Distribution Shift',
    barmode: 'overlay',
    xaxis: {title: 'Wage (USD)', showgrid: true}, yaxis: {title: 'Worker Count', showgrid: true},
    legend: {orientation: 'v', x: 1.05, y: 1}
});
    </script>
</body>
</html>
"""
    write(filename, html)
    println("Plot saved successfully to '$(abspath(filename))'.")
end

function main()
    n_individuals = 100_000
    n_firms = 2000
    n_steps = 110

    # Tiny warmup call before the main simulation to ensure that the JIT compiler has compiled the function
    run_simulation(
        10, 10, 1, 
        rand(-1:9, 10), rand(Float64, 10), rand(Float64, 10), 
        rand(Float64, 10), rand(Float64, 10)
    )

    # Initialize arrays
    Random.seed!(42)
    worker_firm = zeros(Int, n_individuals)
    worker_res_wage = zeros(Float64, n_individuals)
    worker_prod = zeros(Float64, n_individuals)
    
    # Pre-calculate divisors to avoid division by zero
    ind_div = max(1.0, Float64(n_individuals - 1))
    
    for i in 1:n_individuals
        worker_firm[i] = (i % 100 < 15) ? -1 : ((i * 17) % n_firms)
        worker_res_wage[i] = 20.0 + ((i * 137) % n_individuals) / ind_div * 80.0
        worker_prod[i] = 0.5 + ((i * 149) % n_individuals) / ind_div * 1.0
    end

    firm_desired = zeros(Float64, n_firms)
    firm_offered = zeros(Float64, n_firms)
    
    firm_div = max(1.0, Float64(n_firms - 1))
    
    for i in 1:n_firms
        firm_desired[i] = 25.0 + ((i * 13) % n_firms) / firm_div * 40.0
        firm_offered[i] = 15.0 + ((i * 19) % n_firms) / firm_div * 40.0
    end

    # Save initial reservation wage for plotting
    initial_wrw = copy(worker_res_wage)

    println("Running Julia Original labour ABM simulation with Plotting ($(n_individuals) workers, $(n_firms) firms, $(n_steps) steps)...")

    # Run and Benchmark Simulation
    start_time = time()
    result_wf, result_wrw, history = run_simulation(
        n_individuals, n_firms, n_steps,
        worker_firm, worker_res_wage, worker_prod,
        firm_desired, firm_offered
    )
    end_time = time()

    diff = end_time - start_time
    println("Julia: Time = ", round(diff, digits=4), " seconds")

    # Calculate Final Metrics
    unemployed_count = 0
    sum_wage_unemployed = 0.0
    sum_wage_employed = 0.0
    total_active_labor = 0.0

    for i in 1:n_individuals
        if result_wf[i] == -1
            unemployed_count += 1
            sum_wage_unemployed += result_wrw[i]
        else
            sum_wage_employed += result_wrw[i]
            total_active_labor += worker_prod[i]
        end
    end

    employed_count = n_individuals - unemployed_count
    
    unemployment_rate = (unemployed_count / n_individuals) * 100.0
    avg_wage_employed = employed_count > 0 ? (sum_wage_employed / employed_count) : 0.0
    avg_wage_unemployed = unemployed_count > 0 ? (sum_wage_unemployed / unemployed_count) : 0.0
    total_desired_labor = sum(firm_desired)

    # Print Final Metrics
    println("\n==================================================")
    println("      FINAL SIMULATION METRICS (Step ", n_steps, ")")
    println("==================================================")
    println(" Final Unemployment Rate                   : ", round(unemployment_rate, digits=2), "%")
    println(" Final Avg Reservation Wage (Employed)     : \$", round(avg_wage_employed, digits=2))
    println(" Final Avg Reservation Wage (Unemployed)   : \$", round(avg_wage_unemployed, digits=2))
    println(" Final Active Labor Units                  : ", round(Int, total_active_labor))
    println(" Target Desired Labor Demand               : ", round(Int, total_desired_labor))
    println("==================================================\n")

    println("Generating interactive HTML plot...")
    plot_simulation_results(history, initial_wrw, result_wrw; filename="simulation_results_julia.html")
end

main()