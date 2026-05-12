#!/usr/bin/python3

"""
Generate random memory files in the same format as generate_memory_file.py
This script creates memory initialization files with random data for testing.

Usage: python3 generate_random_memory.py [options]
    -a, --addressability <N>    Addressability in bytes (default: 32)
    -o, --output <file>         Output file path (default: memory.lst)
    -s, --size <N>              Total memory size in KB (default: 64)
    -r, --regions <N>           Number of memory regions (default: 4)
    --seed <N>                  Random seed for reproducibility
    --sparse                    Create sparse memory (not all addresses populated)
"""

import sys
import os
import random
import argparse
import math

def generate_random_memory_file(output_file, addressability=32, total_size_kb=64, 
                                num_regions=4, seed=None, sparse=False):
    """
    Generate a memory file with random data in the same format as generate_memory_file.py
    
    Format details:
    - Each line starts with @<address> (8 hex digits, address is divided by addressability)
    - Followed by lines of hex data (each line is addressability*2 hex chars)
    - Bytes are reversed in pairs (little-endian format)
    - Each section ends with a blank line
    
    Args:
        output_file: Path to output .lst file
        addressability: Bytes per memory line (4, 8, 32, etc.)
        total_size_kb: Total size of memory to generate in KB
        num_regions: Number of memory regions to create
        seed: Random seed for reproducibility
        sparse: If True, create gaps between regions
    """
    
    if seed is not None:
        random.seed(seed)
    
    total_bytes = total_size_kb * 1024
    
    # Create memory regions
    regions = []
    if sparse:
        # Create sparse regions at different addresses
        base_addresses = [
            0x00001000,  # Low memory
            0x00010000,  # Medium memory
            0x00100000,  # Higher memory
            0x01000000,  # Even higher
        ]
        for i in range(min(num_regions, len(base_addresses))):
            addr = base_addresses[i]
            size = total_bytes // num_regions
            regions.append((addr, size))
    else:
        # Create contiguous region starting at 0
        regions.append((0, total_bytes))
    
    with open(output_file, 'w') as f:
        for region_start, region_size in regions:
            # Align to addressability
            region_start = (region_start // addressability) * addressability
            region_size = (region_size // addressability) * addressability
            
            # Write address header
            address_offset = region_start >> int(math.log2(addressability))
            f.write(f"@{address_offset:08x}\n")
            
            # Generate random data for this region
            bytes_written = 0
            while bytes_written < region_size:
                # Generate one line of random data (addressability bytes)
                temp_string = ""
                for _ in range(addressability):
                    temp_string += f"{random.randint(0, 255):02x}"
                
                # Reverse bytes in pairs (little-endian format)
                # This matches the format from generate_memory_file.py
                reversed_string = "".join(reversed([temp_string[i:i+2] for i in range(0, len(temp_string), 2)]))
                f.write(reversed_string + '\n')
                
                bytes_written += addressability
            
            # Blank line after each section
            f.write('\n')
    
    print(f"[INFO]  Generated random memory file: {output_file}")
    print(f"        Addressability: {addressability} bytes")
    print(f"        Total size: {total_size_kb} KB")
    print(f"        Regions: {num_regions}")
    print(f"        Format: Compatible with generate_memory_file.py output")


def generate_test_patterns(output_file, addressability=32):
    """
    Generate a memory file with known test patterns instead of random data.
    Useful for debugging and validation.
    """
    
    patterns = [
        # Pattern 1: Sequential counters
        (0x00001000, [i for i in range(256)]),
        
        # Pattern 2: Alternating bits
        (0x00002000, [0xAA, 0x55] * 128),
        
        # Pattern 3: Walking ones
        (0x00003000, [(1 << (i % 8)) for i in range(256)]),
        
        # Pattern 4: Known values
        (0x00004000, [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE] * 32),
        
        # Pattern 5: All zeros
        (0x00005000, [0x00] * 256),
        
        # Pattern 6: All ones
        (0x00006000, [0xFF] * 256),
    ]
    
    with open(output_file, 'w') as f:
        for base_addr, pattern in patterns:
            # Write address header
            address_offset = base_addr >> int(math.log2(addressability))
            f.write(f"@{address_offset:08x}\n")
            
            # Write pattern data
            bytes_written = 0
            temp_string = ""
            
            for byte_val in pattern:
                temp_string += f"{byte_val & 0xFF:02x}"
                bytes_written += 1
                
                if len(temp_string) == 2 * addressability:
                    # Reverse bytes in pairs and write
                    reversed_string = "".join(reversed([temp_string[i:i+2] for i in range(0, len(temp_string), 2)]))
                    f.write(reversed_string + '\n')
                    temp_string = ""
            
            # Write any remaining bytes
            if temp_string:
                reversed_string = "".join(reversed([temp_string[i:i+2] for i in range(0, len(temp_string), 2)]))
                f.write(reversed_string.ljust(2 * addressability, '0') + '\n')
            
            # Blank line after section
            f.write('\n')
    
    print(f"[INFO]  Generated test pattern memory file: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Generate random memory files compatible with generate_memory_file.py format',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 64KB random memory with 32-byte addressability
  python3 generate_random_memory.py -o memory.lst
  
  # Generate 128KB with 4 regions and specific seed
  python3 generate_random_memory.py -s 128 -r 4 --seed 12345 -o memory.lst
  
  # Generate sparse memory (gaps between regions)
  python3 generate_random_memory.py --sparse -o memory.lst
  
  # Generate test patterns instead of random data
  python3 generate_random_memory.py --patterns -o memory.lst
        """
    )
    
    parser.add_argument('-a', '--addressability', type=int, default=32,
                        help='Addressability in bytes (default: 32)')
    parser.add_argument('-o', '--output', type=str, default='memory.lst',
                        help='Output file path (default: memory.lst)')
    parser.add_argument('-s', '--size', type=int, default=64,
                        help='Total memory size in KB (default: 64)')
    parser.add_argument('-r', '--regions', type=int, default=1,
                        help='Number of memory regions (default: 1)')
    parser.add_argument('--seed', type=int, default=None,
                        help='Random seed for reproducibility')
    parser.add_argument('--sparse', action='store_true',
                        help='Create sparse memory with gaps between regions')
    parser.add_argument('--patterns', action='store_true',
                        help='Generate test patterns instead of random data')
    
    args = parser.parse_args()
    
    # Validate addressability
    if args.addressability not in [1, 2, 4, 8, 16, 32, 64]:
        print(f"Warning: Unusual addressability {args.addressability}. Common values: 1, 4, 8, 32")
    
    # Create output directory if needed
    output_dir = os.path.dirname(args.output)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Generate memory file
    if args.patterns:
        generate_test_patterns(args.output, args.addressability)
    else:
        generate_random_memory_file(
            args.output,
            addressability=args.addressability,
            total_size_kb=args.size,
            num_regions=args.regions,
            seed=args.seed,
            sparse=args.sparse
        )
    
    # Print file info
    file_size = os.path.getsize(args.output)
    print(f"        Output file size: {file_size / 1024:.2f} KB")


if __name__ == "__main__":
    main()
