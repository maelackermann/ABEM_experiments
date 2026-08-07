Mini ABM Optimised:

Boundary checking is similarly implemented for both.

Results Julia:
Output:
Running Julia mini labor ABM simulation (100000 workers, 2000 firms, 110 steps)...
Julia: Time = 0.765 seconds

==================================================
      FINAL SIMULATION METRICS (Step 110)
==================================================
 Final Unemployment Rate                   : 8.68%
 Final Avg Reservation Wage (Employed)     : $53.79
 Final Avg Reservation Wage (Unemployed)   : $10.34
 Final Active Labor Units                  : 91372
 Target Desired Labor Demand               : 90000
==================================================


Results C++:
Using the following command to compile labor_mini_abm.cpp:
clang++ -O2 -march=native -mtune=native -flto -fuse-ld=lld -fno-math-errno labor_mini_abm.cpp -o labor_mini_abm.exe

Output:
Running C++ mini labor ABM simulation (100000 workers, 2000 firms, 110 steps)...
C++: Time = 0.625514 seconds

==================================================
      FINAL SIMULATION METRICS (Step 110)
==================================================
 Final Unemployment Rate                  : 8.68%
 Final Avg Reservation Wage (Employed)    : $53.79
 Final Avg Reservation Wage (Unemployed)  : $10.34
 Final Active Labor Units                 : 91371
 Target Desired Labor Demand              : 90000
==================================================