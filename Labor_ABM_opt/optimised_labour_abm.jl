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

    # BOUNDARY CHECKS
    if length(worker_firm) != n_individuals || 
       length(worker_res_wage) != n_individuals || 
       length(worker_prod) != n_individuals
        error("CRITICAL ERROR: Individual vectors do not match n_individuals.")
    end

    if length(firm_desired) != n_firms || 
       length(firm_offered) != n_firms
        error("CRITICAL ERROR: Firm vectors do not match n_firms.")
    end

    # Standard array copying
    wf = copy(worker_firm)
    wrw = copy(worker_res_wage)

    # Pre-allocate tracking arrays
    firm_current_labor = zeros(Float64, n_firms)
    excess = zeros(Float64, n_firms)
    unemployed_indices = zeros(Int, n_individuals)

    @inbounds for step in 1:n_steps
        
        # 1. Compute current labor in a single fast pass
        fill!(firm_current_labor, 0.0)
        for i in 1:n_individuals
            fid = wf[i]
            if fid != -1
                firm_current_labor[fid + 1] += worker_prod[i]
            end
        end

        # Calculate excess labor per firm O(N_firms)
        for fid in 1:n_firms
            excess[fid] = firm_current_labor[fid] - firm_desired[fid]
        end

        # (Reduced from O(N_firms * N_workers) to O(N_workers))
        for i in 1:n_individuals
            fid = wf[i]
            if fid != -1
                # If the worker's firm has excess labor, fire them
                if excess[fid + 1] > 0.0
                    excess[fid + 1] -= worker_prod[i]
                    firm_current_labor[fid + 1] -= worker_prod[i]
                    wf[i] = -1
                    wrw[i] = max(10.0, wrw[i] * 0.9)
                end
            end
        end

        # Gather currently unemployed workers into a dense contiguous array
        num_unemployed = 0
        for i in 1:n_individuals
            if wf[i] == -1
                num_unemployed += 1
                unemployed_indices[num_unemployed] = i
            end
        end

        # 3. Hiring Phase (Iterates only over unemployed workers)
        for fid in 0:(n_firms - 1)
            needed = firm_desired[fid + 1] - firm_current_labor[fid + 1]
            if needed > 0.0
                offered = firm_offered[fid + 1]
                hired_count = 0
                for k in 1:num_unemployed
                    i = unemployed_indices[k]
                    
                    if wf[i] == -1 && offered >= wrw[i]
                        wf[i] = fid
                        firm_current_labor[fid + 1] += worker_prod[i]
                        needed -= worker_prod[i]
                        hired_count += 1
                        wrw[i] = offered * 1.05
                        
                        if needed <= 0.0 || hired_count >= 10
                            break
                        end
                    end
                end
            end
        end

        # 4. Reservation wage decay for remaining unemployed (Vectorized using @simd)
        @simd for k in 1:num_unemployed
            i = unemployed_indices[k]
            if wf[i] == -1
                wrw[i] = max(10.0, wrw[i] * 0.98)
            end
        end
    end

    return wf, wrw
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

    println("Running Julia Optimized labour ABM simulation ($(n_individuals) workers, $(n_firms) firms, $(n_steps) steps)...")

    # Run and Benchmark Simulation
    start_time = time()
    result_wf, result_wrw = run_simulation(
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
end

main()