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
            if excess > 0
                for i in 1:n_individuals
                    if wf[i] == fid
                        excess -= worker_prod[i]
                        wf[i] = -1 # Worker is fired
                        wrw[i] = max(10.0, wrw[i] * 0.9) # Decay reservation wage by 10% but not below 10.0
                        if excess <= 0
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
            if needed > 0
                hired_count = 0
                for i in 1:n_individuals
                    if wf[i] == -1
                        if firm_offered[fid + 1] >= wrw[i]
                            wf[i] = fid
                            firm_current_labor[fid + 1] += worker_prod[i]
                            needed -= worker_prod[i]
                            hired_count += 1
                            wrw[i] = firm_offered[fid + 1] * 1.05 # Increase reservation wage by 5% after being hired
                            if needed <= 0 || hired_count >= 10
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

    # Initialize arrays
    Random.seed!(42)
    worker_firm = rand(-1:(n_firms - 1), n_individuals)
    worker_res_wage = rand(Float64, n_individuals) .* 80.0 .+ 20.0 # Loop Fusion: This line generates random reservation wages for each worker, uniformly distributed between 20 and 100.
    worker_prod = rand(Float64, n_individuals) .* 1.0 .+ 0.5 # Loop Fusion: This line generates random productivity values for each worker, uniformly distributed between 0.5 and 1.5.

    firm_desired = rand(Float64, n_firms) .* 100.0 .+ 50.0 # Loop Fusion: This line generates random desired labor values for each firm, uniformly distributed between 50 and 150.
    firm_offered = rand(Float64, n_firms) .* 60.0 .+ 30.0 # Loop Fusion: This line generates random offered wages for each firm, uniformly distributed between 30 and 90.

    println("Running Julia mini labour ABM simulation ($(n_individuals) workers, $(n_firms) firms, $(n_steps) steps)...")

    # Time starts after this comment so the Random Algorithms do NOT affect the Simulation time!--------------------------------------------------------------------------------------------------

    # First run (Compilation included)
    t_start = time()
    wf_1, wrw_1 = run_simulation(
        n_individuals, n_firms, n_steps,
        worker_firm, worker_res_wage, worker_prod,
        firm_desired, firm_offered
    )
    t_comp = time() - t_start
    println("Julia (1st run - JIT compiling): $(round(t_comp, digits=4)) seconds")

    # Second run (Precompiled)
    t_start = time()
    wf_2, wrw_2 = run_simulation(
        n_individuals, n_firms, n_steps,
        worker_firm, worker_res_wage, worker_prod,
        firm_desired, firm_offered
    )
    t_exec = time() - t_start
    println("Julia (2nd run - Precompiled): $(round(t_exec, digits=4)) seconds")
end

main()