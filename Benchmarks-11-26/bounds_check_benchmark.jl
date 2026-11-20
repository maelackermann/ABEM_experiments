#=
Author: Mael Ackermann
References:
1. Inspired by Axtell, R. L., & Farmer, J. D. (2025). Agent-Based Modeling in Economics and Finance: Past, Present, and Future.
    Journal of Economic Literature, 63(1), 197–287. https://doi.org/10.1257/jel.20221319
2. Inspired by the Oxford INET, macro-main model,
   URL: https://github.com/INET-Complexity/macro-main

Bounds-checking overhead benchmark for the optimised labour ABM.

Runs the SAME optimised algorithm in three variants under identical conditions:

  A  checked        plain Julia, default bounds checks (no @inbounds, no @simd)
  B  inbounds       @inbounds on the step loop + up-front validation
  C  inbounds+simd  B plus @simd on the wage-decay loop (= the optimised
                    repository version, plus a firm-ID range check)

Each variant is warmed up, then timed `n_reps` times; median and minimum are
reported, and the results of all variants are checked to be identical.

Run:   julia bounds_check_benchmark.jl
Cross-check (forces checks everywhere, ignoring every @inbounds):
       julia --check-bounds=yes bounds_check_benchmark.jl
=#

using Random, Statistics, Printf

# ---------------------------------------------------------------------------
# Variant A: language default, bounds checks ON
# ---------------------------------------------------------------------------
function sim_checked(n_individuals, n_firms, n_steps,
                     worker_firm, worker_res_wage, worker_prod,
                     firm_desired, firm_offered)
    wf = copy(worker_firm)
    wrw = copy(worker_res_wage)
    firm_current_labor = zeros(Float64, n_firms)
    excess = zeros(Float64, n_firms)
    unemployed_indices = zeros(Int, n_individuals)

    for step in 1:n_steps
        fill!(firm_current_labor, 0.0)
        for i in 1:n_individuals
            fid = wf[i]
            if fid != -1
                firm_current_labor[fid + 1] += worker_prod[i]
            end
        end
        for fid in 1:n_firms
            excess[fid] = firm_current_labor[fid] - firm_desired[fid]
        end
        for i in 1:n_individuals
            fid = wf[i]
            if fid != -1 && excess[fid + 1] > 0.0
                excess[fid + 1] -= worker_prod[i]
                firm_current_labor[fid + 1] -= worker_prod[i]
                wf[i] = -1
                wrw[i] = max(10.0, wrw[i] * 0.9)
            end
        end
        num_unemployed = 0
        for i in 1:n_individuals
            if wf[i] == -1
                num_unemployed += 1
                unemployed_indices[num_unemployed] = i
            end
        end
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
        for k in 1:num_unemployed
            i = unemployed_indices[k]
            if wf[i] == -1
                wrw[i] = max(10.0, wrw[i] * 0.98)
            end
        end
    end
    return wf, wrw
end

# ---------------------------------------------------------------------------
# Up-front validation used by the @inbounds variants (the "workaround").
# Length checks alone are NOT enough: firm IDs stored in worker_firm are used
# as indices (fid + 1), so their value range has to be validated as well.
# ---------------------------------------------------------------------------
function validate_inputs(n_individuals, n_firms, worker_firm, worker_res_wage,
                         worker_prod, firm_desired, firm_offered)
    if length(worker_firm) != n_individuals ||
       length(worker_res_wage) != n_individuals ||
       length(worker_prod) != n_individuals
        error("CRITICAL ERROR: Individual vectors do not match n_individuals.")
    end
    if length(firm_desired) != n_firms || length(firm_offered) != n_firms
        error("CRITICAL ERROR: Firm vectors do not match n_firms.")
    end
    if !all(fid -> -1 <= fid <= n_firms - 1, worker_firm)
        error("CRITICAL ERROR: worker_firm contains a firm ID outside -1:(n_firms-1).")
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Variants B and C: same code, @inbounds on the step loop, optional @simd
# ---------------------------------------------------------------------------
for (fname, use_simd) in ((:sim_inbounds, false), (:sim_inbounds_simd, true))
    decay_loop = quote
        for k in 1:num_unemployed
            i = unemployed_indices[k]
            if wf[i] == -1
                wrw[i] = max(10.0, wrw[i] * 0.98)
            end
        end
    end
    if use_simd
        decay_loop = :(@simd $(decay_loop.args[2]))
    end

    @eval function $fname(n_individuals, n_firms, n_steps,
                          worker_firm, worker_res_wage, worker_prod,
                          firm_desired, firm_offered)
        validate_inputs(n_individuals, n_firms, worker_firm, worker_res_wage,
                        worker_prod, firm_desired, firm_offered)
        wf = copy(worker_firm)
        wrw = copy(worker_res_wage)
        firm_current_labor = zeros(Float64, n_firms)
        excess = zeros(Float64, n_firms)
        unemployed_indices = zeros(Int, n_individuals)

        @inbounds for step in 1:n_steps
            fill!(firm_current_labor, 0.0)
            for i in 1:n_individuals
                fid = wf[i]
                if fid != -1
                    firm_current_labor[fid + 1] += worker_prod[i]
                end
            end
            for fid in 1:n_firms
                excess[fid] = firm_current_labor[fid] - firm_desired[fid]
            end
            for i in 1:n_individuals
                fid = wf[i]
                if fid != -1 && excess[fid + 1] > 0.0
                    excess[fid + 1] -= worker_prod[i]
                    firm_current_labor[fid + 1] -= worker_prod[i]
                    wf[i] = -1
                    wrw[i] = max(10.0, wrw[i] * 0.9)
                end
            end
            num_unemployed = 0
            for i in 1:n_individuals
                if wf[i] == -1
                    num_unemployed += 1
                    unemployed_indices[num_unemployed] = i
                end
            end
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
            $decay_loop
        end
        return wf, wrw
    end
end

# ---------------------------------------------------------------------------
# Deterministic input data (identical to the thesis scripts)
# ---------------------------------------------------------------------------
function make_inputs(n_individuals, n_firms)
    worker_firm = zeros(Int, n_individuals)
    worker_res_wage = zeros(Float64, n_individuals)
    worker_prod = zeros(Float64, n_individuals)
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
    return worker_firm, worker_res_wage, worker_prod, firm_desired, firm_offered
end

function time_variant(f, args, n_reps)
    f(args...)                         # warm-up at full size (JIT compile)
    times = Float64[]
    local result
    for _ in 1:n_reps
        GC.gc()
        t0 = time_ns()
        result = f(args...)
        push!(times, (time_ns() - t0) / 1e9)
    end
    return times, result
end

function main(; n_individuals = 100_000, n_firms = 2000, n_steps = 110, n_reps = 10)
    inputs = make_inputs(n_individuals, n_firms)
    args = (n_individuals, n_firms, n_steps, inputs...)

    println("Bounds-check benchmark: $(n_individuals) workers, $(n_firms) firms, ",
            "$(n_steps) steps, $(n_reps) timed runs per variant")
    println("Julia $(VERSION), threads = $(Threads.nthreads()), ",
            "check-bounds = $(Base.JLOptions().check_bounds) (0 = default, 1 = yes, 2 = no)\n")

    variants = [("A  checked (default)", sim_checked),
                ("B  @inbounds",          sim_inbounds),
                ("C  @inbounds + @simd",  sim_inbounds_simd)]

    results = Dict{String,Any}()
    medians = Dict{String,Float64}()
    @printf("%-22s %10s %10s %10s\n", "Variant", "median [s]", "min [s]", "max [s]")
    for (name, f) in variants
        times, res = time_variant(f, args, n_reps)
        results[name] = res
        medians[name] = median(times)
        @printf("%-22s %10.4f %10.4f %10.4f\n", name, median(times), minimum(times), maximum(times))
    end

    # All variants must produce bit-identical results
    ref = results[variants[1][1]]
    identical = all(r -> r[1] == ref[1] && r[2] == ref[2], values(results))
    println("\nResults identical across variants: ", identical)

    base = medians[variants[1][1]]
    println("\nOverhead of default bounds checking (median, relative to A):")
    for (name, _) in variants[2:end]
        overhead_s = base - medians[name]
        @printf("  A vs %-20s  %+.4f s  (%+.1f %% of %s)\n",
                strip(name[3:end]), overhead_s, 100 * overhead_s / medians[name], strip(name[3:end]))
    end
end

main()
