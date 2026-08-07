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

    println("Running Julia Original labour ABM simulation ($(n_individuals) workers, $(n_firms) firms, $(n_steps) steps)...")

    # Time starts after this comment so the Random Algorithms do NOT affect the Simulation time!--------------------------------------------------------------------------------------------------

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