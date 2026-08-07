Mini ABM Original with Plotting:

Results Julia:
Running Julia mini labor ABM simulation (100000 workers, 2000 firms, 110 steps)...
Julia: Time = 3.395 seconds

==================================================
      FINAL SIMULATION METRICS (Step 110)
==================================================
 Final Unemployment Rate                   : 8.68%
 Final Avg Reservation Wage (Employed)     : $53.79
 Final Avg Reservation Wage (Unemployed)   : $10.34
 Final Active Labor Units                  : 91372
 Target Desired Labor Demand               : 90000
==================================================

Note:
Julia does Bounds checks.

Results C++:
Using the following command to compile labor_mini_abm_w_plotting.cpp:
clang++ -O2 -march=native -mtune=native -flto -fuse-ld=lld -fno-math-errno labor_mini_abm_w_plotting.cpp -o labor_mini_abm_w_plotting.exe

Running C++ mini labor ABM simulation (100000 workers, 2000 firms, 110 steps)...
C++: Time = 3.48381 seconds

==================================================
      FINAL SIMULATION METRICS (Step 110)
==================================================
 Final Unemployment Rate                   : 8.682%
 Final Avg Reservation Wage (Employed)     : $53.7865
 Final Avg Reservation Wage (Unemployed)   : $10.3405
 Final Active Labor Units                  : 91371
 Target Desired Labor Demand               : 90000
==================================================