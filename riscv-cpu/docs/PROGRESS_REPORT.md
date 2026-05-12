# Progress Report 1 - CP1

We have made all the basic components of the front end of the CPU and the memory interface is done. We have the queue, fetch, adapter and arbitrator done. Currently the arbitrator only does arbitration for I-cache and allows both read and write operations for later use. Routing between Dcache and Icache is still pending until needed for future CPs. We have also finished the first revision of the block design. All the components that are going into the CPU are mapped out. Most of the interfaces for the block diagram are fleshed out, a few interfaces that we were unsure of have been left for later. 

# Progress Report 2 - CP2

All CP2 requirements have been completed. The processor successfully executes all RV32I immediate/register instructions and RV32M multiply/divide operations. OoO execution is demonstrated with independent operations completing before dependent long latency operations. Division by zero is handled per RISC-V specification. We have also already begun working on CP3 plus advanced features including branch prediction (GShare predictor and Branch Target Buffer) and finished pipelined cache.
