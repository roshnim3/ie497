# Random Memory File Generator

## Overview

`generate_random_memory.py` generates random memory initialization files in the **exact same format** as `generate_memory_file.py` outputs. This is useful for testing hardware modules like adapters, caches, and memory controllers without needing to compile C/assembly programs.

## Format Compatibility

The generated files are 100% compatible with the DRAM controller and testbenches that expect memory files from `generate_memory_file.py`. The format is:

```
@<address in hex>
<data line 1 - hex bytes reversed in pairs>
<data line 2 - hex bytes reversed in pairs>
...
<blank line>
```

## Usage

### Basic Usage

```bash
# Generate 64KB random memory with 32-byte addressability (default)
python3 generate_random_memory.py -o memory.lst

# Generate for adapter testbench
python3 generate_random_memory.py -o ../testcode/memory.lst -a 32 -s 16
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-a, --addressability <N>` | Addressability in bytes (1, 4, 8, 32, etc.) | 32 |
| `-o, --output <file>` | Output file path | memory.lst |
| `-s, --size <N>` | Total memory size in KB | 64 |
| `-r, --regions <N>` | Number of memory regions | 1 |
| `--seed <N>` | Random seed for reproducibility | None |
| `--sparse` | Create sparse memory with gaps | False |
| `--patterns` | Generate test patterns instead of random | False |

### Examples

**1. Generate memory for adapter testbench (32-byte bursts):**
```bash
python3 generate_random_memory.py -a 32 -o memory.lst -s 16 --seed 42
```

**2. Generate memory with known test patterns:**
```bash
python3 generate_random_memory.py --patterns -o memory.lst
```
This creates patterns like:
- Sequential counters (0x00, 0x01, 0x02, ...)
- Alternating bits (0xAA, 0x55, 0xAA, 0x55, ...)
- Walking ones (0x01, 0x02, 0x04, 0x08, ...)
- Known values (DEADBEEF, CAFEBABE, etc.)

**3. Generate sparse memory with multiple regions:**
```bash
python3 generate_random_memory.py -r 4 --sparse -o memory.lst
```
This creates memory at addresses: 0x1000, 0x10000, 0x100000, 0x1000000

**4. Generate reproducible random memory:**
```bash
python3 generate_random_memory.py --seed 12345 -o memory.lst
```
Using the same seed will always generate the same data.

## Integration with Makefile

You can integrate this with your Makefile:

```makefile
# Generate random memory if MEM is not specified
run_vcs_adapter_tb: vcs/adapter_tb
	@if [ -z "$(MEM)" ]; then \
		python3 ../bin/generate_random_memory.py -o ../testcode/memory.lst -a 32 -s 16; \
		$(MAKE) run_vcs_adapter_tb MEM=../testcode/memory.lst; \
	else \
		cd vcs && ./adapter_tb +MEMLST_ECE411="$(shell readlink -f $(MEM))"; \
	fi
```

## Use Cases

### 1. Adapter Testing
Test the adapter module that converts between 256-bit cache lines and 64-bit bursts:
```bash
python3 generate_random_memory.py -a 32 -o memory.lst -s 16
make run_vcs_adapter_tb MEM=memory.lst
```

### 2. Cache Testing
Generate larger memory files for cache testing:
```bash
python3 generate_random_memory.py -a 32 -o memory.lst -s 256
make run_vcs_cache_tb MEM=memory.lst
```

### 3. DRAM Controller Testing
Test the DRAM controller with various memory layouts:
```bash
# Sparse memory
python3 generate_random_memory.py --sparse -r 8 -s 128 -o memory.lst

# Dense random memory
python3 generate_random_memory.py -s 512 -o memory.lst
```

### 4. Debugging with Known Patterns
Use test patterns to debug data path issues:
```bash
python3 generate_random_memory.py --patterns -o memory.lst
```

## Technical Details

### Addressability
The addressability parameter determines how many bytes are on each data line:
- **1 byte**: Each line has 2 hex characters
- **4 bytes**: Each line has 8 hex characters (word-aligned)
- **8 bytes**: Each line has 16 hex characters (double-word)
- **32 bytes**: Each line has 64 hex characters (cache line for this project)

### Byte Reversal
The script matches the little-endian byte order used by `generate_memory_file.py`:
- Bytes are written in pairs: `01 23 45 67` becomes `67452301`
- This matches the RISC-V little-endian memory model

### Memory Regions
When using `--sparse` with `-r <N>` regions:
- Region 1: 0x00001000
- Region 2: 0x00010000
- Region 3: 0x00100000
- Region 4: 0x01000000

Each region gets an equal share of the total memory size.

## Comparison with generate_memory_file.py

| Feature | generate_memory_file.py | generate_random_memory.py |
|---------|------------------------|---------------------------|
| Input | C/Assembly/ELF files | None (generates random) |
| Output format | Memory .lst file | Memory .lst file (identical format) |
| Use case | Compile programs for CPU | Test memory subsystems |
| Data content | Actual program/data | Random or patterns |
| Speed | Requires compilation | Instant generation |

Both produce **identical format** files that work with the DRAM controller and testbenches.
